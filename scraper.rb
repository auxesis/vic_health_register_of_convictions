require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'active_support'
require 'active_support/core_ext'
require 'pry'
require 'reverse_markdown'

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

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def get(url)
  @agent ||= Mechanize.new
  @agent.ca_file = './bundle.pem' if File.exists?('./bundle.pem')
  begin
    @agent.get(url)
  rescue OpenSSL::SSL::SSLError => e
    puts "[info] There was an SSL error when performing a HTTP GET to #{url}"
    puts "[info] The error was: #{e.message}"
    puts "[info] There's a good chance there's a problem with the certificate bundle."
    puts "[info] Find out what the problem could be at: https://www.ssllabs.com/ssltest/analyze.html?d=www2.health.vic.gov.au"
    puts "[info] Exiting!"
    exit(2)
  end
end

def extract_detail(page)
  details = {}

  data_list = page.search('div#main div dl').first.children.map {|e| e.text? ? nil : e }.compact
  data_list.each_slice(2).with_index do |(key, value), index|
    dt = key.text
    if field = @mappings[dt]
      if field == 'description'
        text = ReverseMarkdown.convert(value.children.map(&:to_s).join)
      else
        text = value.text.blank? ? nil : value.text
      end
      details.merge!({field => text})
    else
      raise "unknown field for '#{dt}'"
    end
  end

  return details
end

def extract_notices(page)
  notices = []
  page.search('div.contentInfo div.table-container tbody tr').each do |el|
    notices << { 'link' => "#{base}#{el.search('a').first['href']}" }
  end
  notices
end

def build_conviction(conviction)
  page    = get(conviction['link'])
  details = extract_detail(page)
  puts "Extracting #{details['address']}"

  conviction.merge!(details)
end

def geocode(notice)
  @addresses ||= {}

  address = notice['address']

  if @addresses[address]
    puts "Geocoding [cache hit] #{address}"
    location = @addresses[address]
  else
    puts "Geocoding #{address}"
    a = Geokit::Geocoders::GoogleGeocoder.geocode(address)
    location = {
      'lat' => a.lat,
      'lng' => a.lng,
    }

    @addresses[address] = location
  end

  notice.merge!(location)
end

def base
  'https://www2.health.vic.gov.au/public-health/food-safety/convictions-register'
end

def existing_record_ids
  return @cached if @cached
  @cached = ScraperWiki.select('link from data').map {|r| r['link']}
rescue SqliteMagic::NoSuchTable
  []
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

def extract_convictions(page)
  convictions = []

  # Build up basic records
  elements = page.search('div.listing-container ol li')
  elements.each do |el|
    conviction = extract_basic_detail(el)

    detail_url = el.search('a').first['href']
    conviction.merge!({'link' => detail_url})

    convictions << conviction
  end

  convictions
end


def main
  page = get(base)

  convictions = extract_convictions(page)
  puts "### Found #{convictions.size} convictions"
  new_convictions = convictions.select {|r| !existing_record_ids.include?(r['link']) }
  puts "### There are #{new_convictions.size} new convictions"

  new_convictions.map! {|c| build_conviction(c) }
  new_convictions.map! {|c| geocode(c) }

  # Serialise
  ScraperWiki.save_sqlite(['link'], new_convictions)

  puts 'Done'
end

main()
