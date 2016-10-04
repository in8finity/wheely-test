require 'eventmachine'
require 'em-http'
require 'evma_httpserver'
require 'oj'

class NearestCarsEndpointServer < EM::Connection
  include EM::HttpServer

   def post_init
     super
     no_environment_strings
   end

  def process_http_request
    # the http request details are available via the following instance variables:
    #   @http_protocol
    #   @http_request_method
    #   @http_cookie
    #   @http_if_none_match
    #   @http_content_type
    #   @http_path_info
    #   @http_request_uri
    #   @http_query_string
    #   @http_post_content
    #   @http_headers
    response = EM::DelegatedHttpResponse.new(self)
    http = EventMachine::HttpRequest.new( "http://127.0.0.1:8081" ).get
    http.callback do
      response.status = http.response_header.status
      response.content_type "application/json"
      
      response.content = http.response
      
      response.send_response
    end
    http.errback do
      response.status = 500
      response.content = Oj.dump {:error: "Unable to access the ETA micro service"}
      response.send_response
    end

  end
end

EM.run{
  EM.start_server '0.0.0.0', 8080, NearestCarsEndpointServer
}