require 'json'

module AwsSetuyaku
  class ExchangeRate
    class << self
      def usd_to(currency)
        url = "http://rate-exchange.appspot.com/currency?from=usd&to=jpy"
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.path + "?from=usd&to=#{currency}")
        response = http.request(request)
        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)['rate']
        else
          nil
        end
      end
    end
  end
end
