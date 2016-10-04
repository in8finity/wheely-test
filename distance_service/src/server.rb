require 'eventmachine'
require 'evma_httpserver'
require 'em-http'
require 'oj'

class NearestCarsServiceServer < EM::Connection
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

    #TODO: check endpoint url

    #TODO: check cache and it's expiration
    #TODO: query for cars if no cache or high chances that cache data is obsolete
    #TODO: update data in cache
    #TODO: return found data as response (in bson or pmesg)

    response = EM::DelegatedHttpResponse.new(self)
    response.status = 200
    response.content_type "text/json"
    response.content = Oj.dump({test: "it"})
    response.send_response

    end
end

EM.run{
  EM.start_server '0.0.0.0', 8081, NearestCarsServiceServer
}