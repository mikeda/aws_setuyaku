$LOAD_PATH.unshift('./lib')
require 'aws_setuyaku'
require 'pp'
require 'pry'
require 'net/ssh'
require 'aws-sdk-v1'

REGION = 'ap-northeast-1'
SSH_USER = 'mikeda'

# それぞれ70%までしか使わない
MAX_CPU = 0.7
MAX_MEM = 0.7

# 全体で30%以上コスト削減が可能な場合は障害とみなす
ALERT_RATE = 0.3

def get_load(host)
  yesterday_sar = "/var/log/sa/sa#{(Date.today - 1).strftime("%d")}"

  max_cpu_usage = nil
  max_mem_used = nil
  Net::SSH.start(host, SSH_USER) do |ssh|
    min_cpu_idle = ssh.exec!("LANG=C sar -f /var/log/sa/sa30 | grep all | grep -v Average | awk '{print $NF}' | sort -r | tail -n 1").chomp.to_f
    max_cpu_usage = 1 - ( min_cpu_idle / 100)
  
    sar_mem = ssh.exec!("LANG=C sar -r -f /var/log/sa/sa30 | egrep '^..:..:.. *[1-9]'");
    max_mem_used = 0
    sar_mem.each_line do |line|
      _, _, kbmemused, _, kbbuffers, kbcached, _ = line.chomp.split(/\s+/)
      used = kbmemused.to_i - kbbuffers.to_i - kbcached.to_i
      max_mem_used = used if used > max_mem_used
    end
  end
  return max_cpu_usage, max_mem_used.to_f / (1024*1024)
end

AWS.config( region: REGION )
ec2 = AWS::EC2.new
ec2_spec = AwsSetuyaku::Spec::Ec2.new

instances = []
ec2.instances.each do |instance|
  next if instance.status != :running

  name = instance.tags['Name']
  dns_name = instance.dns_name
  instance_type = instance.instance_type
  spec = ec2_spec.spec(REGION, instance_type)

  max_cpu_usage, max_mem_used = get_load(dns_name)
  ecu = spec[:ecu] * max_cpu_usage
  cheap_spec = ec2_spec.most_cheap_spec(REGION, ecu, MAX_CPU, max_mem_used, MAX_MEM)

  instances << {
    name: name,
    max_cpu_usage: max_cpu_usage,
    max_mem_used: max_mem_used,
    spec: spec,
    cheap_spec: cheap_spec
  }
end

yen_rate = AwsSetuyaku::ExchangeRate.usd_to('jpy')

total_current_cost = 0
total_ideal_cost = 0
puts ["インスタンス名", "昨日のCPU/Mem", "既存サイズ", "最適サイズ"].join("\t")
instances.each do |instance|
  current_cost = (instance[:spec][:price] * yen_rate * 24 * 30).to_i
  ideal_cost = (instance[:cheap_spec][:price] * yen_rate * 24 * 30).to_i
  total_current_cost += current_cost
  total_ideal_cost += ideal_cost
  puts [
    instance[:name],
    "#{(instance[:max_cpu_usage]*100).to_i}%/#{instance[:max_mem_used].round(2)}GB",
    "#{instance[:spec][:name]}/#{current_cost}円/月",
    instance[:spec].equal?(instance[:cheap_spec]) ? "" : "#{instance[:cheap_spec][:name]}/#{ideal_cost}円/月"
  ].join("\t")
end
puts ""
puts "合計"
puts "  現状コスト:#{total_current_cost}円/月"
puts "  最適コスト:#{total_ideal_cost}円/月"
puts "  \e[31mムダコスト:#{total_current_cost - total_ideal_cost}円/月\e[0m"

muda_rate = (total_current_cost.to_f - total_ideal_cost) / total_current_cost
if muda_rate > ALERT_RATE
  puts ""
  puts "\e[31m#{muda_rate.round(2) * 100}%のムダが発生してます！！！\e[0m"
  exit 1
end
