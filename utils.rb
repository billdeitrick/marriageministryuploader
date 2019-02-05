require 'pco_api'

# Utility functions for parsing, API calls, and inputs.
class Utils # rubocop:disable Metrics/ClassLength
  GIVEN_NAME_FIELDS = [
    'where[first_name]',
    'where[given_name]',
    'where[nickname]'
  ].freeze

  # Initialize the utilities class
  def initialize(pco)
    @pco = pco
  end

  # Process the row for a given class
  def process_class_row(students, mentors, session, mm_class)
    results = []

    # Parse names and get PCO data
    process_student_names(students, mm_class, session) do |result|
      results << result
    end

    # Validate student search results, prompting for manual intervention
    results.map! { |result| validate_student_result(result) }

    # Add mentors
    results.map! do |result|
      result[:mentors] = mentors
      result
    end

    results
  end

  # Validates student search results (as best as possible)
  # Will prompt for manual input if necessary
  def validate_student_result(result)
    (valid = check_multiple(result)) unless (valid = check_empty(result))

    if valid.nil?
      result[:pco_id] = result[:pco_id][0]
      result[:pco_name] = result[:pco_name][0]
    else
      result[:pco_id] = valid['data']['id']
      result[:pco_name] = valid['data']['attributes']['name']
    end
    result
  end

  # Check for multiple people results found from PCO search
  def check_multiple(result)
    return nil if result[:pco_id].size == 1

    puts "Multiple results found in PCO for #{result[:name]} " \
         "(#{result[:session]} #{result[:mm_class]}): #{result[:pco_id]}. " \
         'Enter index of correct id:'

    index = gets.chomp.to_i

    format_check_multiple_result(result, index)
  end

  # Format a result for handling multple search results
  def format_check_multiple_result(result, index)
    {
      'data' => {
        'id' => result[:pco_id][index],
        'attributes' => { 'name' => result[:pco_name][index] }
      }
    }
  end

  # Check for an empty result from PCO search
  def check_empty(result)
    return nil unless result[:pco_id].empty?

    puts "No results found in PCO for #{result[:name]} " \
          "(#{result[:session]} #{result[:mm_class]}). Enter PCO ID:"
    pco_call { @pco.people.v2.people[gets.chomp].get }
  end

  # Make a call to PCO. Handles rate limiting automagically.
  def pco_call(&block)
    loop do
      begin
        return yield block
      rescue PCO::API::Errors::ClientError => e
        # Guard clause: push up to the caller if it's not a rate limit exception
        raise unless e.message.match?(/Rate limit exceeded/)

        # A bit of a hack (should parse response headers for sleep time...)
        sleep(1)
      end
    end
  end

  # Process text potentially containing names and return results from PCO
  def process_student_names(text, mm_class, session)
    self.class.get_names(text) do |names|
      names.each do |name|
        pco_person = fuzzy_search_pco_people_by_name(name)
        yield build_search_result(name, mm_class, session, pco_person)
      end
    end
  end

  # Find a PCO person using all possible name variants
  def fuzzy_search_pco_people_by_name(person)
    GIVEN_NAME_FIELDS.each_index do |ndx|
      call_result = pco_call do
        @pco.people.v2.people.__send__(:get,
                                       GIVEN_NAME_FIELDS[ndx] => person[:first],
                                       'where[last_name]' => person[:last])
      end
      return call_result if final_fuzzy_search_result?(call_result, ndx)
    end
  end

  # Get names from a string extracted from the spreadsheet
  def self.get_names(input)
    # One last name for two people
    if (match = /^(\w+)\s\&\s(\w+)\s(\w+)$/.match(input.strip))
      yield extract_same_last_names(match)
    # Two last names for two people
    elsif (match = /^(\w+)\s(\w+)\s\&\s(\w+)\s(\w+)$/.match(input.strip))
      yield extract_different_last_names(match)
    end
  end

  # Parse date headers
  # Return match object if text is a date header, nil if it is not
  def self.parse_date_headers(text)
    /[0-9]{4}\s(Spring|Fall)+/.match text.strip
  end

  # Parse session from text if available
  # Return session if it was found, nil if it wasn't
  def self.parse_session_from_text(text)
    return if text.nil? || !(match = Utils.parse_date_headers(text))

    yield match[0]
  end

  private

  # Build hash for PCO People search results
  def build_search_result(name, mm_class, session, pco_person)
    {
      name: name,
      pco_name: pco_person['data'].map { |item| item['attributes']['name'] },
      pco_id: pco_person['data'].map { |item| item['id'] },
      session: session,
      mm_class: mm_class
    }
  end

  # Determine if passed result is the final result of a fuzzy name search
  def final_fuzzy_search_result?(call_result, ndx)
    !call_result['data'].empty? || ndx == GIVEN_NAME_FIELDS.size - 1
  end

  # Private class methods
  class << self
    private

    # Extract same last names to data structure
    def extract_same_last_names(match)
      [
        {
          first: match.captures[0],
          last: match.captures[2]
        },
        {
          first: match.captures[1],
          last: match.captures[2]
        }
      ]
    end

    # Extract different last names to data structure
    def extract_different_last_names(match)
      [
        {
          first: match.captures[0],
          last: match.captures[1]
        },
        {
          first: match.captures[2],
          last: match.captures[3]
        }
      ]
    end
  end
end
