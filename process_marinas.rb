require "json"
require "csv"
require "net/http"
require "uri"

GOOGLE_API_KEY = ENV["GOOGLE_API_KEY"]
HOUSING_PRICES = CSV.read("housing_prices.csv", headers: true)

def main
  # Step 1: Read the GeoJSON file
  file_path = "marinas.geojson"
  geojson_content = File.read(file_path)
  geojson = JSON.parse(geojson_content)

  # Step 2: Process the features
  new_features = geojson["features"].map.with_index do |feature, index|
    print "\n#{index}" if index % 20 == 0
    print "."
    geometry = feature["geometry"]

    # Process based on geometry type
    case geometry["type"]
    when "Point"
      # Keep the point as is
      new_geometry = geometry
    when "Polygon"
      # Replace with the first point of the first ring
      first_point = geometry["coordinates"][0][0]
      new_geometry = {
        "type" => "Point",
        "coordinates" => first_point
      }
    when "MultiPolygon"
      # Replace with the first point of the first polygon's first ring
      first_point = geometry["coordinates"][0][0][0]
      new_geometry = {
        "type" => "Point",
        "coordinates" => first_point
      }
    else
      raise "Unsupported geometry type: #{geometry["type"]}"
    end

    zip_code = get_zip_code(new_geometry["coordinates"][1], new_geometry["coordinates"][0])
    price = price_for_zip_code(zip_code) if zip_code

    # Return a new feature with the modified geometry
    {
      "type" => "Feature",
      "geometry" => new_geometry,
      "properties" => feature["properties"].merge("zip_code" => zip_code, "Average Housing Cost" => price),
      "id" => feature["id"]
    }
  end.compact # Remove nil values from skipped geometries

  # Step 3: Create a new GeoJSON FeatureCollection
  new_geojson = {
    "type" => "FeatureCollection",
    "features" => new_features
  }

  # Step 4: Write the new GeoJSON to a file
  output_file_path = "combined.geojson"
  File.write(output_file_path, JSON.pretty_generate(new_geojson))

  puts "New GeoJSON file with only points created at #{output_file_path}"
end

def get_zip_code(lat, lon)
  url = URI.parse("https://maps.googleapis.com/maps/api/geocode/json?latlng=#{lat},#{lon}&key=#{GOOGLE_API_KEY}")

  # Create an HTTP request
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(url.request_uri)

  # Make the HTTP request
  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    data = JSON.parse(response.body)

    if data["results"] && !data["results"].empty?
      address_components = data["results"].map { |r| r["address_components"] }.flatten
      # Find the component that contains the postal code
      postal_code_component = address_components.find do |component|
        component["types"].include?("postal_code")
      end

      if postal_code_component
        postal_code_component["long_name"]
      else
        puts "ZIP Code not found for the given coordinates (#{lat}, #{lon})"
        nil
      end
    else
      puts "No results found for the given coordinates (#{lat}, #{lon})"
      nil
    end
  else
    puts "Failed to retrieve data from Google Maps API (#{response.code})"
    nil
  end
end

def price_for_zip_code(zip_code)
  price_row = HOUSING_PRICES.find { |row| row[2] == zip_code }
  if price_row
    price = price_row[-1]
    sprintf("%.2f", price.to_f).gsub(/(\d)(?=(\d{3})+\.)/, '\1,')
  else
    puts "no price found for zip code #{zip_code}"
    nil
  end
end

if __FILE__ == $PROGRAM_NAME
  main
end
