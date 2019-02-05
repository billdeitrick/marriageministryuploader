require 'CSV'
require_relative 'utils'
require 'pco_api'
require 'dotenv/load'

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

# Grab data
data = CSV.read('data/parser_output.csv')

# Setup

## Mentors
mentor_field = utils.pco_call do
  pco.people.v2.field_definitions[ENV['MENTOR_FIELD']].get(
    include: 'field_options'
  )
end
mentor_hash = mentor_field['included'].each.with_object({}) do |obj, hash|
  hash[obj['attributes']['value']] = obj['id']
end

## SDOE Sessions
sdoe_session_field = utils.pco_call do
  pco.people.v2.field_definitions[ENV['SDOE_SESSION_FIELD']].get(
    include: 'field_options'
  )
end
sdoe_session_hash = sdoe_session_field['included'].each.with_object({}) do |obj, hash|
  hash[obj['attributes']['value']] = obj['id']
end

## MR&MRS Sessions
mrmrs_session_field = utils.pco_call do
  pco.people.v2.field_definitions[ENV['MRMRS_SESSION_FIELD']].get(
    include: 'field_options'
  )
end
mrmrs_session_hash = mrmrs_session_field['included'].each_with_object({}) do |obj, hash|
  hash[obj['attributes']['value']] = obj['id']
end

# Validate all mentor values in data, for sanity (skipping header row)
data[1..-1].each do |row|
  # Check Mentor value
  unless mentor_hash.key?(row[4]) || row[4].nil?
    raise(Exception,
          "#{row[4]} for #{row[0]} does not appear to be a valid mentor.")
  end

  # Check class session value
  if row[3] == 'SDOE'
    unless sdoe_session_hash.key?(row[2])
      raise(Exception,
            "#{row[2]} for #{row[0]} does not appear to be " \
            'a valid class session.')
    end
  elsif row[3] == 'MR&MRS'
    unless mrmrs_session_hash.key?(row[2])
      raise(Exception,
            "#{row[2]} for #{row[0]} does not appear to be " \
            'a valid class session.')
    end
  end
end

count = 0

# We should have valid data by now. Let's commit it.
data[1..-1].each do |row|
  # Sanity check
  begin
    pco.people.v2.people[row[1]].get
  rescue
    puts "Sanity check failed. Couldn't find #{row[0]}, #{row[1]}."
  end

  # Mentors
  unless row[-1].nil?
    mentors_data = Marshal.load(Marshal.dump(FIELD_DATUM_TEMPLATE))
    mentors_data[:data][:attributes][:value] = row[4]
    mentors_data[:data][:relationships][:field_definition][:data][:id] =
      ENV['MENTOR_FIELD']

    begin
      utils.pco_call do
        pco.people.v2.people[row[1]].field_data.post(mentors_data)
      end
    rescue PCO::API::Errors::UnprocessableEntity
      puts "Mentors already entered for #{row[0]}, #{row[1]}."
    end
  end

  # SDOE/MR&MRS
  class_data = Marshal.load(Marshal.dump(FIELD_DATUM_TEMPLATE))
  class_data[:data][:attributes][:value] = row[2]
  if row[3] == 'SDOE'
    class_data[:data][:relationships][:field_definition][:data][:id] =
      ENV['SDOE_SESSION_FIELD']
  elsif row[3] == 'MR&MRS'
    class_data[:data][:relationships][:field_definition][:data][:id] =
      ENV['MRMRS_SESSION_FIELD']
  end

  begin
    utils.pco_call do
      pco.people.v2.people[row[1]].field_data.post(class_data)
    end
  rescue PCO::API::Errors::UnprocessableEntity
    puts "Class already entered for #{row[0]}, #{row[1]}."
  end

  count += 1

  puts "Processed #{count}"
end
