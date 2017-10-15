# frozen_string_literal: true

require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'active_support'
require 'active_support/core_ext'
require 'pry'
require 'reverse_markdown'
require 'dotenv'
Dotenv.load

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
  'Court:' => 'court'
}

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def save_to_wayback_machine(url)
  debug "Saving #{url} to the Wayback Machine."
  require 'net/http'

  save_url = 'http://web.archive.org/save/' + url
  uri = URI(save_url)

  Net::HTTP.start(uri.host, uri.port) do |http|
    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
    unless response.is_a? Net::HTTPSuccess
      info("Attempt to save #{url} to Wayback Machine failed.")
      info('Exiting!')
      exit(2)
    end
  end
end

def get(url)
  @agent ||= Mechanize.new
  @agent.ca_file = './bundle.pem' if File.exist?('./bundle.pem')
  begin
    response = @agent.get(url)
    save_to_wayback_machine(url)
    return response
  rescue OpenSSL::SSL::SSLError => e
    info "There was an SSL error when performing a HTTP GET to #{url}"
    info "The error was: #{e.message}"
    info %(There's a good chance there's a problem with the certificate bundle.)
    info 'Find out what the problem could be at: https://www.ssllabs.com/ssltest/analyze.html?d=www2.health.vic.gov.au'
    info 'Exiting!'
    exit(2)
  end
end

def extract_detail(page)
  details = {}

  data_list = page.search('div#main div dl').first.children.map { |e| e.text? ? nil : e }.compact
  data_list.each_slice(2).with_index do |(key, value), _index|
    dt = key.text
    if field = @mappings[dt]
      if field == 'description'
        text = ReverseMarkdown.convert(value.children.map(&:to_s).join)
      else
        text = value.text.blank? ? nil : value.text
      end
      details[field] = text
    else
      raise "unknown field for '#{dt}'"
    end
  end

  details
end

def extract_notices(page)
  notices = []
  page.search('div.contentInfo div.table-container tbody tr').each do |el|
    notices << { 'link' => "#{base}#{el.search('a').first['href']}" }
  end
  notices
end

def debug(msg)
  puts '[debug] ' + msg
end

def info(msg)
  puts '[info] ' + msg
end

def build_conviction(conviction)
  page    = get(conviction['link'])
  details = extract_detail(page)
  debug "Extracting #{conviction['link']}"

  conviction.merge!(details)
end

def geocode_cache(address, value = nil)
  @cache ||= {}
  if value
    @cache[address] = value
  else
    @cache[address]
  end
end

def geocode(record)
  address = record['address']

  if geocode_cache(address)
    location = geocode_cache(address)
  else
    response = Geokit::Geocoders::GoogleGeocoder.geocode(address)
    location = { 'lat' => response.lat, 'lng' => response.lng }
    geocode_cache(address, location)
  end

  record.merge!(location)
end

def base
  'https://www2.health.vic.gov.au/about/convictions-register'
end

def existing_record_ids
  return @cached if @cached
  @cached = ScraperWiki.select('link from data').map { |r| r['link'] }
rescue SqliteMagic::NoSuchTable
  []
end

# Index of conviction records
def convictions_index_at_source
  page = get(base)
  page.search('div.listing-container ol li').map do |el|
    { 'link' => el.search('a').first['href'] }
  end
end

def new_convictions
  info "There are #{existing_record_ids.size} existing records that have been scraped"
  info "There are #{convictions_index_at_source.size} records at #{base}"
  convictions_index_at_source.reject { |r| existing_record_ids.include?(r['link']) }
end

def main
  # Set an API key if provided
  Geokit::Geocoders::GoogleGeocoder.api_key = ENV['MORPH_GOOGLE_API_KEY'] if ENV['MORPH_GOOGLE_API_KEY']
  records = new_convictions
  info "There are #{records.size} records we haven't seen before at #{base}"
  # Scrape details new records
  records.map! { |r| build_conviction(r) }
  records.map! { |r| geocode(r) }
  # Save new records
  ScraperWiki.save_sqlite(['link'], records)
  info 'Done'
end

main if $PROGRAM_NAME == __FILE__
