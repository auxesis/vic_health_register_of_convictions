# frozen_string_literal: true

require 'scraperwiki'
require 'mechanize'
require 'geokit'
require 'active_support'
require 'active_support/core_ext'
require 'reverse_markdown'
require 'configatron/core'
require 'dotenv'
Dotenv.load

# rubocop:disable Metrics/MethodLength
def mappings
  {
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
end
# rubocop:enable Metrics/MethodLength

def scrub(text)
  text.gsub!(/[[:space:]]/, ' ') # convert all utf whitespace to simple space
  text.strip
end

def agent
  return @agent if @agent
  @agent = Mechanize.new
  @agent.ca_file = './bundle.pem' if File.exist?('./bundle.pem') && config.ssl.use_ca_bundle?
  @agent.ssl_version = config.ssl.version
  @agent
end

def save_to_wayback_machine(url)
  debug "Saving #{url} to the Wayback Machine."
  save_url = 'http://web.archive.org/save/' + url
  agent.get(save_url)
rescue Mechanize::Error => e
  info("Attempt to save #{url} to Wayback Machine failed.")
  info(e.message)
  info('Exiting!')
  exit(2)
end

# rubocop:disable Metrics/MethodLength
def config
  return @config if @config&.to_hash&.any?
  @config = Configatron::RootStore.new
  @config.configure_from_hash(
    ssl: {
      use_ca_bundle?: ENV['MORPH_USE_CA_BUNDLE'] != 'false',
      version: ENV['MORPH_SSL_VERSION'] || 'TLSv1_2'
    },
    disable_wayback_machine?: ENV['MORPH_DISABLE_WAYBACK_MACHINE'] == 'true',
    google: {
      api_key: ENV['MORPH_GOOGLE_API_KEY']
    }
  )
  debug "Config: #{@config.to_hash}"
  @config
end
# rubocop:enable Metrics/MethodLength

def get(url)
  save_to_wayback_machine(url) unless config.disable_wayback_machine?
  agent.get(url)
rescue OpenSSL::SSL::SSLError => e
  info "There was an SSL error when performing a HTTP GET to #{url}: #{e.message}"
  debug 'This was the backtrace'
  info %(There's a good chance there's a problem with the certificate bundle.)
  info 'Find out what the problem could be at: https://www.ssllabs.com/ssltest/analyze.html?d=www2.health.vic.gov.au'
  exit(2)
end

def debug(msg)
  puts '[debug] ' + msg
end

def info(msg)
  puts '[info] ' + msg
end

def build_key_value_from_mapping(key, value)
  field = mappings[key.text]
  raise "unknown field for '#{key.text}'" unless field
  text = if field == 'description'
           ReverseMarkdown.convert(value.children.map(&:to_s).join)
         else
           value.text.blank? ? nil : value.text
         end
  [field, text]
end

def extract_detail_elements(page)
  page.search('div#main div dl').first.children.map { |e| e.text? ? nil : e }.compact
end

def scrape_conviction(record)
  debug "Extracting #{record['link']}"

  page = get(record['link'])
  details = extract_detail_elements(page).each_slice(2).map do |(key, value)|
    build_key_value_from_mapping(key, value)
  end

  record.merge!(Hash[details])
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

def test_ssl_methods
  working = OpenSSL::SSL::SSLContext::METHODS.select do |method|
    agent = Mechanize.new
    agent.ssl_version = method
    debug "Testing SSL method: #{method}"
    begin
      agent.get(base)
    rescue => e
      false
    end
  end
  debug 'These are the working SSL methods: ' + working.join(', ')
  exit
end

def main
  test_ssl_methods
  # Set an API key if provided
  Geokit::Geocoders::GoogleGeocoder.api_key = config.google.api_key
  records = new_convictions
  info "There are #{records.size} records we haven't seen before at #{base}"
  # Scrape details new records
  records.map! { |r| scrape_conviction(r) }
  records.map! { |r| geocode(r) }
  # Save new records
  ScraperWiki.save_sqlite(['link'], records)
  info 'Done'
end

main if $PROGRAM_NAME == __FILE__
