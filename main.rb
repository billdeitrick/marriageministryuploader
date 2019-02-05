require 'CSV'
require_relative 'utils'
require 'pco_api'
require 'dotenv/load'

pco = PCO::API.new(basic_auth_token: ENV['PCO_AUTH_TOKEN'],
                   basic_auth_secret: ENV['PCO_AUTH_SECRET'])

utils = Utils.new(pco)

data = CSV.read('data/Master-Table 1.csv')

output = []

cur_sdoe = nil
cur_mrmrs = nil

data.each do |row|
  # Column 1 contains SDOE, column 6 contains MR&MRS
  # If we don't have data for either, skip
  next if row[1].nil? && row[6].nil?

  # Process SDOE data if we have it
  unless row[1].nil?
    # Update the current SDOE session if needed
    Utils.parse_session_from_text(row[1]) do |session|
      cur_sdoe = session unless session.nil?
    end

    # Process this row for the current class and add to output
    utils.process_class_row(row[1], row[2], cur_sdoe, 'SDOE').each do |result|
      output << result
    end
  end

  # Process MR & MRS data if we have it
  unless row[6].nil? # rubocop:disable Style/Next
    # Update the current SDOE session if needed
    Utils.parse_session_from_text(row[6]) do |session|
      cur_mrmrs = session unless session.nil?
    end

    # Process this row for the current class and add to output
    utils.process_class_row(row[6],
                            row[7],
                            cur_mrmrs,
                            'MR&MRS').each do |result|
      output << result
    end
  end
end

csv_headers = output.first.keys
csv_headers.delete(:name)

CSV.open('data/parser_output.csv', 'wb', headers: csv_headers) do |csv|
  csv << csv_headers
  output.each do |row|
    csv << row
  end
end
