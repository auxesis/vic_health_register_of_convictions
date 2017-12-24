# frozen_string_literal: true

require 'spec_helper'

describe 'vic_health_register_of_convictions' do
  describe '.convictions_index_at_source' do
    it 'returns an index of convictions', :aggregate_failures do
      VCR.use_cassette('convictions_index') do
        expect(convictions_index_at_source).to_not be nil
        convictions_index_at_source.each do |conviction|
          expect(conviction['link']).to be_url
        end
      end
    end
  end

  describe '.new_convictions' do
    it 'returns only new convictions' do
      VCR.use_cassette('convictions_index', allow_playback_repeats: true) do
        expect(new_convictions).to_not be_empty
        ScraperWiki.save_sqlite(['link'], new_convictions)
        expect(new_convictions).to be_empty
      end
    end
  end

  describe '.geocode' do
    let(:record) do
      {
        'address' => '333 George Street Sydney 2000',
        'link' => 'https://google.com/'
      }
    end

    it 'adds latitude and longitude to record' do
      VCR.use_cassette('gmaps_geocode_address') do
        geocode(record)
        expect(record['lat']).to eq(-33.8668093)
        expect(record['lng']).to eq(151.2070304)
      end
    end
  end

  describe '.get' do
    before { unset_environment_variable('MORPH_DISABLE_WAYBACK_MACHINE') }

    it 'saves the page to the Wayback Machine' do
      VCR.use_cassette('wayback_machine_save') do
        get(base)
        expect(WebMock).to have_requested(:get, base)
        expect(WebMock).to have_requested(:get, 'web.archive.org/save/' + base)
      end
    end

    context 'when there is a Wayback Machine failure' do
      it 'exits' do
        VCR.use_cassette('wayback_machine_save_failure') do
          expect { get('aesaestoststaestsnt') }.to raise_error(SystemExit)
        end
      end
    end

    context 'when Wayback Machine is disabled' do
      before { set_environment_variable('MORPH_DISABLE_WAYBACK_MACHINE', 'true') }

      it 'does not make requests to the Wayback Machine' do
        VCR.use_cassette('wayback_machine_bypass') do
          get(base)
          expect(WebMock).to have_requested(:get, base)
          expect(WebMock).to_not have_requested(:get, 'web.archive.org/save/' + base)
        end
      end
    end

    after { restore_env }
  end

  describe '.scrape_conviction' do
    let(:record) do
      {
        'link' => 'https://www2.health.vic.gov.au/about/convictions-register/register-of-convictions-Malkem-Makhoul'
      }
    end

    it 'adds fields to record', :aggregate_failures do
      VCR.use_cassette('scrape_conviction') do
        scrape_conviction(record)
        record.each_value do |value|
          expect(value).to_not be nil
        end
      end
    end

    it 'converts description to markdown' do
      VCR.use_cassette('scrape_conviction') do
        scrape_conviction(record)
        expect(record['description']).to_not have_tag('li')
      end
    end
  end

  describe 'config' do
    describe '.use_ca_bundle' do
      context 'no value' do
        before { unset_environment_variable('MORPH_USE_CA_BUNDLE') }
        it 'is enabled' do
          expect(config.use_ca_bundle?).to be true
        end
      end
      context 'set true' do
        before { set_environment_variable('MORPH_USE_CA_BUNDLE', 'true') }
        it 'is enabled' do
          expect(config.use_ca_bundle?).to be true
        end
      end
      context 'set false' do
        before { set_environment_variable('MORPH_USE_CA_BUNDLE', 'false') }
        it 'is disabled' do
          expect(config.use_ca_bundle?).to be false
        end
      end
      after { restore_env }
    end
  end

  after { config&.reset! }
end
