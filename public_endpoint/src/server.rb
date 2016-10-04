require 'eventmachine'
require 'em-http'
require 'evma_httpserver'
require 'oj'
require 'msgpack'

class NearestCarsEndpointServer < EM::Connection
  include EM::HttpServer

   def post_init
     super
     no_environment_strings
   end

   def decode_coords query_str 
    throw Exception.new("Failed to parse paramteres ") if(query_str.nil?)

    params = query_str.split("&")
    parsed_params = {}
    params = params.each{|param|
       param_parts = param.split "="
       parsed_params[param_parts[0].to_sym] = param_parts[1]
     } if params.count > 0
  
    {latitude: parsed_params[:lat].to_f, longitude:parsed_params[:long].to_f}
  end

  def process_http_request
    begin
      response = EM::DelegatedHttpResponse.new(self)
      point = decode_coords(@http_query_string)
      http = EventMachine::HttpRequest.new( "http://127.0.0.1:8081/?lat=#{point[:latitude]}&long=#{point[:longitude]}}" ).get
      http.callback do
        response.status = http.response_header.status
        response.content_type "application/json"
        
        payload = MessagePack.unpack http.response

        response.content = Oj.dump(payload)
        
        response.send_response
      end
      http.errback do
        response.status = 500
        response.content = Oj.dump({error: "Unable to access the ETA micro service"})
        response.send_response
      end
    rescue Exception=>e
      response = EM::DelegatedHttpResponse.new(self)
      response.status = 500
      response.content_type "text/msgpack"
      response.content = Oj.dump({error: e.message})
      response.send_response
    end

  end
end

EM.run{
  EM.start_server '0.0.0.0', 8080, NearestCarsEndpointServer
}