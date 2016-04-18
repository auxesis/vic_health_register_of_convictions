require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'pry'

convictions = []

# Fetch the page
agent = Mechanize.new
page = agent.get("https://www2.health.vic.gov.au/public-health/food-safety/convictions-register")

# Build up basic records
elements = page.search('div.listing-container ol li')
elements.each do |el|
  conviction = {}
  conviction['trading_name'] = el.at('h3').text.strip
  party, address, council = el.search('div.content em').text.split(/\s*\|\s*/)
  conviction['party_served'] = party
  conviction['address'] = address
  conviction['council'] = council
  convictions << conviction
end

puts "Found #{convictions.size} convictions"

# Geocode
convictions.each do |conviction|
  puts "Geocoding #{conviction["address"]}"
  a = Geokit::Geocoders::GoogleGeocoder.geocode(conviction['address'])
  location = {
    'lat' => a.lat,
    'lng' => a.lng,
  }
  conviction.merge!(location)
end

# Serialise
convictions.each do |conviction|
  ScraperWiki.save_sqlite(["address"], conviction)
end

puts "Done"
