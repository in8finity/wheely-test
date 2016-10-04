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

  def process_http_request

    response = EM::DelegatedHttpResponse.new(self)
    http = EventMachine::HttpRequest.new( "http://127.0.0.1:8081" ).get
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

  end
end

EM.run{
  EM.start_server '0.0.0.0', 8080, NearestCarsEndpointServer
}