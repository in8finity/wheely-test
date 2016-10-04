require 'em-hiredis'
require 'msgpack'
 require 'geohash'

class EtaService

	@@instance = nil

	def self.instance(redis_connection=nil, error_callback=nil)
		return @@instance if @@instance
		throw Exception.new "You have to specify redis connection" if(!@@instance && redis_connection.nil?)
		@@instance = self.new redis_connection	
		@@error_callback = error_callback if error_callback
		@@instance
	end

	def initialize redis_connection=nil
		#TODO: redis should be injected into service
		@redis = redis_connection
		populate #it should be done by cache warmer here it's only as a part of test task
	end

	def populate
		return if @populating
		@populating = true
		@populated = false
		@taxis_populated = 0
		i = 1
		population_track_callback = Proc.new {
				@taxis_populated += 1
				puts "Populated redis with #{@taxis_populated} taxis"
				if(@taxis_populated == 5 )
					puts "Populated redis with taxis"
					@populated = true
				end
			}

		(1..5).each{ |i|
			update_taxi_point({longitude: 12.2324+rand(10)/10000.0, latitude: 23.1131+rand(10)/10000.0}, {available:"true", id:"Taxi_#{i}"}.to_msgpack) {population_track_callback.call()}
		}
	end

	def update_taxi_point point, taxi_info, &callback
		#puts "Adding taxt at #{point.inspect}"
		defferable = @redis.geoadd("Taxies", point[:longitude], point[:latitude], taxi_info.to_msgpack)
		defferable.callback {
		 	yield 
		}
		defferable.errback { |e|
		    puts e # => #<RuntimeError: ERR Operation against a key holding the wrong kind of value>
		    @@error_callback.call(e)
		    #puts e.redis_error
		}
	end

	def set_cached_eta point, eta
		geocahe_value = GeoHash.encode(point[:longitude], point[:latitude], precision = 4) #prec=4  is 111.111/10^5 = 100 meters (for 60 km/h = 1km/min its enough)
		defferable = @redis.set(geocahe_value, eta)
		defferable.callback { |result|
			@redis.expire(geocahe_value, 6) #6 seconds ~ 100 meters for car moving on full speed in the city (60 km/h)
		}
		defferable.errback { |e|
		    #puts e # => #<RuntimeError: ERR Operation against a key holding the wrong kind of value>
		    @@error_callback.call(e)
		}
	end

	def get_cached_eta point, &callback
		geocahe_value = GeoHash.encode(point[:longitude], point[:latitude], precision=4) #4 decimals is 111.111/10^5 = 100 meters (for 60 km/h = 1km/min its enough)
		defferable = @redis.get(geocahe_value)
		defferable.callback { |result|
			yield result
		}
	end

	def find_nearest_taxies point, &callback
		have_cached = false
		defferable = @redis.georadius("Taxies", point[:longitude], point[:latitude], 10000, "m", "COUNT", 3, "WITHDIST")
		defferable.callback {|result| 
			#puts "Nearest Taxies found"
			yield result if !have_cached
		}
		defferable.errback { |e|
		    puts e # => #<RuntimeError: ERR Operation against a key holding the wrong kind of value>
		    @@error_callback.call(e)
		}
	end


	def is_data_ready?
		@populated
	end

	def nearest_cars_with_distance point, &callback
		find_nearest_taxies( point) {|result| 
			#puts "Found nearest taxies"
			#puts result.inspect
			yield result
		}
		
		#TODO: query it from redis
		# cars = []
		# cars << {longitude: 12.2324, latitude: 23.1131, distance: 12.2}
		# cars << {longitude: 34.2324, latitude: 63.1131, distance: 10.2}
		# cars << {longitude: 22.2324, latitude: 5.1131, distance: 3.2}
		# cars
		#TODO: get cars from redis and call callback calculating the real distance
	end

	def eta_for_point point, &callback
		get_cached_eta(point){|result| 
			puts "Cached val: #{result.inspect}"
			if(result.nil?)
				average_distance(point){|distance| 
					eta = distance*1.5/1000.0
					set_cached_eta(point, eta)
					yield eta
				}
			else
				yield result
			end
		} 
		#point {:longitude: 12.2324, :latitude: 23.1131}
		#average_distance(point){|distance| yield distance*1.5}
	end

	def average_distance point, &callback
		nearest_cars_with_distance(point) {|cars|
			#puts cars.inspect 
			#puts cars[0][1].to_f
			result = cars.reduce(0.0){|a,c| a += c[1].to_f}/cars.count
			yield result
		}
	end

	def decode_coords request
		{longitude: 12.2324, latitude: 23.1131}
	end
end