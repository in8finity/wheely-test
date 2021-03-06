require 'eventmachine'
require 'evma_httpserver'
require 'em-http'
require 'em-hiredis'
require 'oj'
require 'msgpack'
require File.dirname(__FILE__)+'/eta_service'

class ETAServiceServer < EM::Connection
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
    #TODO: handle timeouts

    service = EtaService.instance
    begin
      point = decode_coords(@http_query_string)
      service.eta_for_point(point) { |eta|
      response = EM::DelegatedHttpResponse.new(self)
      response.status = 200
      response.content_type "text/msgpack"
      response.content = ({"estimated_time": eta}).to_msgpack
      response.send_response
    }

    rescue Exception=>e
      response = EM::DelegatedHttpResponse.new(self)
      response.status = 500
      response.content_type "text/msgpack"
      response.content = Oj.dump({error: e.message}).to_msgpack
      response.send_response
    end
    

    end
end

EM.run{
  redis_connection = EM::Hiredis.connect("redis://127.0.0.1:6379/")
  error_callback = Proc.new { |err|
    puts err.inspect
    response = EM::DelegatedHttpResponse.new(self)
    response.status = 500
    response.content_type "text/msgpack"
    response.content = ({error: err.message}).to_msgpack
    response.send_response

  }
  EtaService.instance(redis_connection, error_callback).populate
  
  EM.start_server '0.0.0.0', 8081, ETAServiceServer
}