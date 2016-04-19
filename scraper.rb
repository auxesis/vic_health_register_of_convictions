require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'pry'

@indicies = [
  'conviction_number',
  'trade_name',
  'company_name',
  'address',
  'convicted_persons_or_company',
  'relationship_of_person',
  'conviction_date',
  'court_decision',
  'sentence_imposed',
  'prosecution_brought_by',
  'description',
]

def fetch_detail(detail_url)
  details = {}
  indicies = @indicies.dup

  page = @agent.get(detail_url)
  data_list = page.search('div#main div dl').first.children.map {|e| e.text? ? nil : e }.compact
  indicies.delete(3) if data_list.size == 22
  data_list.each_slice(2).with_index do |(key, value), index|
    details.merge!({indicies[index] => value.text})
  end

  return details
end

def extract_basic_detail(el)
  conviction = {}

  conviction['trading_name'] = el.at('h3').text.strip
  party, address, council = el.search('div.content em').text.split(/\s*\|\s*/)
  conviction['party_served'] = party
  conviction['address'] = address
  conviction['council'] = council

  return conviction
end

convictions = []

# Fetch the page
@agent = Mechanize.new
page = @agent.get("https://www2.health.vic.gov.au/public-health/food-safety/convictions-register")

# Build up basic records
elements = page.search('div.listing-container ol li')
elements.each do |el|
  conviction = extract_basic_detail(el)

  detail_url = el.search('a').first['href']
  details    = fetch_detail(detail_url)
  conviction.merge!(details)

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
