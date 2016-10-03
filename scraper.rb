require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'active_support'
require 'active_support/core_ext'
require 'pry'

# Set an API key if provided
Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']

@mappings = {
  'Conviction number:' => 'conviction_number',
  'Trade name of food business:' => 'trading_name',
  'Company name (if applicable):' => 'company_name',
  'Address of premises where offence(s) occurred:' => 'address',
  'Name of convicted person(s) or company:' => 'convicted_persons_or_company',
  'Relationship of convicted person(s) to the business:' => 'relationship_of_person',
  'Date of conviction:' => 'conviction_date',
  'Court decision:' => 'court_decision',
  'Sentence and/or order imposed:' => 'sentence_imposed',
  'Prosecution brought by or for:' => 'prosecution_brought_by',
  'Description of offense(s):' => 'description',
  'Court:' => 'court',
}

def fetch_detail(detail_url)
  details = {}

  page = @agent.get(detail_url)
  data_list = page.search('div#main div dl').first.children.map {|e| e.text? ? nil : e }.compact
  data_list.each_slice(2).with_index do |(key, value), index|
    dt = key.text
    if @mappings[dt]
      val = value.text.blank? ? nil : value.text
      details.merge!({@mappings[dt] => val})
    else
      raise "unknown field for '#{dt}'"
    end
  end

  return details
end

def extract_basic_detail(el)
  conviction = {}

  conviction['trading_name'] = el.at('h3').text.strip
  party, address, council = el.search('div.content em').text.split(/\s*\|\s*/)
  conviction['convicted_persons_or_company'] = party
  conviction['address'] = address
  conviction['prosecution_brought_by'] = council

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
  conviction.merge!({'link' => detail_url})

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
ScraperWiki.save_sqlite(['conviction_number'], convictions)

puts "Done"
