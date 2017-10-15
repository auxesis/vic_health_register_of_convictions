# frozen_string_literal: true

require 'spec_helper'

describe 'vic_health_register_of_convictions' do
  describe '.convictions' do
    it 'returns an index of convictions', :aggregate_failures do
      VCR.use_cassette('convictions_index') do
        expect(convictions).to_not be nil
        convictions.each do |conviction|
          expect(conviction['link']).to be_url
        end
      end
    end
  end
end
