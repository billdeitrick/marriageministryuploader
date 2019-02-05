require_relative 'utils'
require 'pco_api'
require 'dotenv/load'

# Quick script to speed data entry

# Constants
FIELD_DATUM_TEMPLATE = {
  data: {
    type: 'FieldDatum',
    attributes: {},
    relationships: {
      field_definition: {
        data: {
          type: 'FieldDefinition'
        }
      }
    }
  }
}.freeze

# Get ready to speak to PCO API
pco = PCO::API.new(basic_auth_token: ENV['PCO_AUTH_TOKEN'],
                   basic_auth_secret: ENV['PCO_AUTH_SECRET'])
utils = Utils.new(pco)

# Repeat until CTRL + C
loop do # rubocop:disable Metrics/BlockLength
  # We're going to get two names at once since couples' data will match
  people_ids = []

  loop do
    break if people_ids.size == 2

    puts 'Enter first and last name to search'
    name = gets.chomp.split

    search_results = utils.fuzzy_search_pco_people_by_name(first: name[0],
                                                           last: name[1])

    if search_results['data'].size == 1
      people_ids << search_results['data'][0]['id']
    elsif search_results['data'].size > 1
      ids = search_results['data'].each.with_object([]) do |res, ary|
        ary << res['id']
      end
      puts "Found matching ids #{ids}, please enter " \
           'the index of the one you want:'
      ndx = gets.chomp
      people_ids << ids[ndx.to_i]
    elsif search_results['data'].empty?
      puts 'No search results found. Please try again.'
    end
  end

  # Get start year
  puts 'Enter start year'
  s_year = gets.chomp
  # Get end year
  puts 'Enter end year'
  e_year = gets.chomp

  people_ids.each do |person_id|
    # Start year
    unless s_year.empty?
      sy_data = Marshal.load(Marshal.dump(FIELD_DATUM_TEMPLATE))
      sy_data[:data][:attributes][:value] = s_year
      sy_data[:data][:relationships][:field_definition][:data][:id] =
        ENV['START_YEAR_FIELD']

      utils.pco_call do
        pco.people.v2.people[person_id].field_data.post(sy_data)
      end
    end

    # End year
    unless e_year.empty?
      ey_data = Marshal.load(Marshal.dump(FIELD_DATUM_TEMPLATE))
      ey_data[:data][:attributes][:value] = e_year
      ey_data[:data][:relationships][:field_definition][:data][:id] =
        ENV['END_YEAR_FIELD']

      utils.pco_call do
        pco.people.v2.people[person_id].field_data.post(ey_data)
      end
    end

    puts "Person #{person_id} updated."
  end
end
