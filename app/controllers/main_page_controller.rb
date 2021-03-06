class MainPageController < ApplicationController

	require 'net/http'
  require 'will_paginate/array'
  require 'rexml/document'
  require 'json'


  before_filter :get_trains_info,    :only => [:fetch, :train_info, :all]
  before_filter :get_station_coords,  :only => [:station_info]

  def get_station_coords
    rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getAllStationsXML"
    
    @xml_data = Net::HTTP.get_response(URI.parse(rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @allStationsWithCoords = {}
    @doc.elements.each('ArrayOfObjStation/objStation') do |name|
      hash = {}
      hash[name.elements['StationCode'].text.strip] = {  lat: name.elements['StationLatitude'].text,
                                                  lon: name.elements['StationLongitude'].text,
                                                  stationName: name.elements['StationDesc'].text }
      @allStationsWithCoords.merge!(hash)
    end 
  end

  def get_trains_info
    rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getCurrentTrainsXML"
    
    @xml_data = Net::HTTP.get_response(URI.parse(rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @allTrains = []
    #root = @doc.root
    @doc.elements.each('ArrayOfObjTrainPositions/objTrainPositions') do |name|
      message = name.elements['PublicMessage'].text.split('\\n')
      hash = {desc: message[1],lat: name.elements['TrainLatitude'].text, lon: name.elements['TrainLongitude'].text, 
                                                    code: name.elements['TrainCode'].text }
       
      @allTrains << hash
    end
  end

	def fetch
		
    
    @convert = @allStations.assoc('Belfast Central')
    @station = @convert.to_json
  end
	
  def all
    @home_page = 'all_stations'

    if current_user
      @favs = User.find_by_id(current_user.id).favourites
    end

    rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getCurrentTrainsXML_WithTrainType?TrainType=#{params[:data]}"
    
    @xml_data = Net::HTTP.get_response(URI.parse(rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @allStations = []
    #root = @doc.root
    @doc.elements.each('ArrayOfObjTrainPositions/objTrainPositions') do |name|
      message = name.elements['PublicMessage'].text.split('\\n')
      hash = {desc: message[1],lat: name.elements['TrainLatitude'].text, lon: name.elements['TrainLongitude'].text, 
                                                    code: name.elements['TrainCode'].text }
       
      @allStations << hash
    end
    
    gon.returned_train = false
    @stations = @allStations.paginate(:page => params[:page])

    respond_to do |format|
      format.html
      format.json { render json: @allStations.to_json }
    end
  end

  def train_info
    
    @home_page = 'station_info'
        
    begin
      @returned_train = @allTrains.detect {|station| station[:code] == params[:data] }
      gon.returned_train = @returned_train
    rescue => e
      flash[:danger] = "Server returned invalid train code. Soz!!" 
      redirect_to :back and return
    end
    
    #start get train movements
    #train = @allStations[(params[:data])]
    @date = Time.now.strftime("%d%B%Y")
    
    rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getTrainMovementsXML?TrainId=#{params[:data]}&TrainDate=#{@date}"
    
    @xml_data = Net::HTTP.get_response(URI.parse(rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @allTrains = []
    @doc.elements.each('ArrayOfObjTrainMovements/objTrainMovements') do |train| 
      arrival = train_info_arrival(train.elements['ExpectedArrival'].text)

      departure = train_info_depart(train.elements['ExpectedDeparture'].text)      
      
      hash = { stop:train.elements['LocationFullName'].text,
                stopCode:train.elements['LocationCode'].text,
                origin:train.elements['TrainOrigin'].text,
                exArrival:arrival,
                exDepart: departure,
                current?:train.elements['StopType'].text,
                destination:train.elements['TrainDestination'].text}
      @allTrains << hash
      
    end 

    respond_to do |format|
      format.html
      format.json { render json: { stops: @allTrains, coords: @returned_train } }
    end
  end

  def station_info   
    @home_page = "orange" 
    @returned_station_code = params[:data]
    if current_user
      if User.find_by_id(current_user.id)
      @favs = User.find_by_id(current_user).favourites.where(station: params[:data]) 
    end 
    end   
    begin 
      @stationMessage = @allStationsWithCoords[params[:data]][:stationName]      
    rescue => e      
      flash[:danger] = "Server returned invalid station code. Soz!!" 
      redirect_to :back and return
    end
    @rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getStationDataByCodeXML_WithNumMins?StationCode=#{params[:data]}&NumMins=90"
    @xml_data = Net::HTTP.get_response(URI.parse(@rail_url)).body
    @stationDoc = REXML::Document.new(@xml_data)
    @stationByTime = []

    @stationDoc.elements.each('ArrayOfObjStationData/objStationData') do |station|
      arrival = station_info_arrival(station.elements['Exparrival'].text)
      
      depart = station_info_depart(station.elements['Expdepart'].text)

      
      hash = { origin:station.elements['Origin'].text,
               destination: station.elements['Destination'].text,
               arrival: arrival,
               depart: depart,
               due: station.elements['Duein'].text,
               code: station.elements['Traincode'].text.strip }
      @stationByTime << hash
    end
     
    gon.returned_train = @allStationsWithCoords[params[:data]]
    @stationByTime
    

    respond_to do |format|
    format.html
    format.json { render json: {station:@stationByTime, coords:@allStationsWithCoords[params[:data]] } }
    format.js { render :js => "gonMap()"}
    end
  end  

  def get_all_stations
    @rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getAllStationsXML_WithStationType?StationType=#{params[:type]}"
    @xml_data = Net::HTTP.get_response(URI.parse(@rail_url)).body
    
    @allStations = Hash.from_xml(@xml_data)['ArrayOfObjStation']['objStation']
    @returnAllStations = @allStations.sort_by { |station| station['StationDesc'] }
    render json: @returnAllStations
  end

  def search_stations
    @home_page = 'station_info'
    @rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getStationsFilterXML?StationText=#{params[:data]}"
    @xml_data = Net::HTTP.get_response(URI.parse(@rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @searchResults = []
    @doc.elements.each('ArrayOfObjStationFilter/objStationFilter') do |station|
      hash = { stationDesc: station.elements['StationDesc'].text, stationCode: station.elements['StationCode'].text.strip }
      @searchResults << hash
    end

    # @searchResults = Hash.from_xml(@xml_data)['ArrayOfObjStationFilter']['objStationFilter']
    # Rails.cache.write('results', @searchResults)
    respond_to do |format|
      format.html
      format.json { render json: @searchResults }
    end
  end

  def nearby_stations
    @home_page = 'station_info' 
    rail_url = "http://api.irishrail.ie/realtime/realtime.asmx/getAllStationsXML"
    
    @xml_data = Net::HTTP.get_response(URI.parse(rail_url)).body
    @doc = REXML::Document.new(@xml_data)
    @allStationsWithCoords = {}
    @distances = []
    @doc.elements.each('ArrayOfObjStation/objStation') do |name|
      distance = Geocoder::Calculations.distance_between( params[:coords],
        [name.elements['StationLatitude'].text,name.elements['StationLongitude'].text])
      if distance <= 30
        hash = { code:name.elements['StationCode'].text.strip, lat: name.elements['StationLatitude'].text,
                                                    lon: name.elements['StationLongitude'].text,
                                                    stationName: name.elements['StationDesc'].text,
                                                    distance: distance }
        @distances << hash
      end
    end 

    @sortedStationsByDistance = @distances.sort_by { |station| station[:distance] }
    gon.sortedDistances = @sortedStationsByDistance
    gon.returned_train = @sortedStationsByDistance
    respond_to do |format|
      format.html
      format.json { render json: @sortedStationsByDistance }
      
    end
    #http://rubydoc.info/gems/rails-geocoder/0.9.10/frames
  end

  
end
