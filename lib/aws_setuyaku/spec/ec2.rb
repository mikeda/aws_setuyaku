module AwsSetuyaku::Spec
  class Ec2
    ECU = {
      't1.micro' => 1.0,
      't2.micro' => 3.0,
      't2.small' => 3.0,
      't2.medium' => 6.5
    }

    def initialize
      current_spec = get_spec("http://a0.awsstatic.com/pricing/1/ec2/linux-od.min.js")
      previous_spec = get_spec("http://a0.awsstatic.com/pricing/1/ec2/previous-generation/linux-od.min.js")
      @spec = {}
      current_spec.each do |region, types|
        @spec[region] = current_spec[region].merge(previous_spec[region]) if previous_spec[region]
      end
    end

    def spec(region, name)
      @spec[region][name]
    end

    def most_cheap_spec(region, ecu, max_cpu_usage, mem, max_mem_usage)
      @spec[region].values
        .sort_by{|s| s[:price]}
        .find{|s| s[:ecu] * max_cpu_usage >= ecu && s[:mem] * max_mem_usage >= mem}
    end

    private 

    def get_spec(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.path)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        m = response.body.match(/\A.*?callback\((.*)?\);\z/m)
        content = JSON.parse(m.captures[0].gsub(/(\w+):/, '"\1":'))

        reorder_spec(content)
      else
        nil
      end
    end

    def reorder_spec(content)
      spec = {}
      content['config']['regions'].each do |region|
        region['instanceTypes'].each do |types|
          types['sizes'].each do |size|
            spec[region['region']] ||= {}
            spec[region['region']][size['size']] = {
              name: size['size'],
              vcpu: size['vCPU'].to_i,
              ecu: ECU[size['size']] || size['ECU'].to_f,
              mem: size['memoryGiB'].to_f,
              price: size['valueColumns'][0]['prices']['USD'].to_f
            }
          end
        end
      end
      spec
    end

  end
end
