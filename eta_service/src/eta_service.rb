require 'em-hiredis'
require 'msgpack'
 require 'geohash'

class EtaService

	TIME_TO_PASS_100_METERS = 6 #6 seconds
	GEOHASH_PRECISION_100_METERS = 4 #prec=4  is 111.111/10^5 = 100 meters (for 60 km/h = 1km/min its enough)

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
				if(@taxis_populated == 10 )
					puts "Populated redis with taxis"
					@populated = true
				end
			}

		(1..5).each{ |i|
			update_taxi_point({longitude: 12.2324+rand(10)/10000.0, latitude: 23.1131+rand(10)/10000.0}, {available:true, id:"Taxi_#{i}"}.to_msgpack) {population_track_callback.call()}
		}
	end

	def update_taxi_point point, taxi_info, &callback
		#puts "Adding taxt at #{point.inspect}"
		#if updating taxi it could be added to available list or removed from it (so we are not handling complex filtering of taxies)
		defferable = @redis.geoadd("AvailableTaxi", point[:longitude], point[:latitude], taxi_info.to_msgpack)
		defferable.callback {
		 	yield 
		}
		defferable.errback { |e|
		    @@error_callback.call(e)
		    #puts e.redis_error
		}
	end

	#TODO: it's should be in separate class
	def set_cached_eta point, eta
		geocahe_value = GeoHash.encode(point[:longitude], point[:latitude], precision = GEOHASH_PRECISION_100_METERS) 
		defferable = @redis.set(geocahe_value, eta)
		defferable.callback { |result|
			@redis.expire(geocahe_value, TIME_TO_PASS_100_METERS) 
		}
		defferable.errback { |e|
		    @@error_callback.call(e)
		}
	end

	def get_cached_eta point, &callback
		geocahe_value = GeoHash.encode(point[:longitude], point[:latitude], precision=GEOHASH_PRECISION_100_METERS) #4 prec is 111.111/10^5 = 100 meters (for 60 km/h = 1km/min its enough)
		defferable = @redis.get(geocahe_value)
		defferable.callback { |result|
			yield result
		}
	end

	def find_nearest_taxies point, distance, &callback
		defferable = @redis.georadius("AvailableTaxi", point[:longitude], point[:latitude], distance, "m", "COUNT", 3, "WITHDIST")
		defferable.callback {|result| 
			#nearest taxi found
			yield result
		}
		defferable.errback { |e|
		    @@error_callback.call(e)
		}
	end


	def is_data_ready?
		@populated
	end

	def eta_for_point point, &callback
		get_cached_eta(point){|result| 
			if(result.nil?)
				average_distance(point){|distance| 
					eta = distance*1.5/1000.0 #distance in meters, check find_nearest_taxies
					set_cached_eta(point, eta)
					yield eta
				}
			else
				yield result
			end
		} 
	end

	def average_distance point, &callback
		find_nearest_taxies(point, 10000) {|cars|
			result = cars.reduce(0.0){|acc,car| acc += car[1].to_f}/cars.count
			yield result
		}
	end
end