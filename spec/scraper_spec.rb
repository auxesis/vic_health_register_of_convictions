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
end
