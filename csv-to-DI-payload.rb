#!/usr/bin/env ruby

require 'optparse'
require 'csv'
require 'json'
require 'date'

MAX_IDENTITIES_PER_FILE = 100000
CURRENT_DATE = DateTime.now.iso8601

# Values from the Command-line
$DATASET_ID = nil
$NAMESPACE = nil
$DISPLAY_NAME = nil
$DESCRIPTION = nil
$OUTPUT_DIR = "."
$VERBOSITY = 1  # 0 = quiet, 1 = normal, 2 = verbose, 3 = very verbose

def very_verbose; $VERBOSITY >= 3; end
def verbose; $VERBOSITY >= 2; end
def normal_verbosity; $VERBOSITY >= 1; end
def quiet_verbosity; $VERBOSITY < 1; end

def parse_args
  options = { header: nil }
  OptionParser.new do |opts|
    opts.banner = "Usage: csv-to-DI-payload.rb [options] input_file1 [input_file2 ...]"

    opts.on("--column COLUMN", "Column index (1-based) or name. Defaults to the first column.") { |v| options[:column] = v }
    opts.on("--namespace NAMESPACE", "Namespace value for each identity (e.g., 'email' or 'ECID').") { |v| options[:namespace] = v }
    opts.on("--dataset-id DATASET_ID", "ID of dataset to be targeted, or 'ALL'.") { |v| options[:dataset_id] = v }
    opts.on("--display-name DISPLAY_NAME", "Display name for the work order.") { |v| options[:display_name] = v }
    opts.on("--description DESCRIPTION", "Description for the work order.") { |v| options[:description] = v }
    opts.on("--csv", "Force input files to be read as CSV.") { options[:format] = :csv }
    opts.on("--tsv", "Force input files to be read as TSV.") { options[:format] = :tsv }
    opts.on("--txt", "Force input files to be read as TXT.") { options[:format] = :txt }
    opts.on("--[no-]header", "Indicate whether the input files have headers (default true except for txt)") { |v| options[:header] = v }
    opts.on("--quiet", "Suppress output") { options[:verbosity] = 0 }
    opts.on("--verbose", "-v", "Enable verbose output.") { options[:verbosity] = 2 }
    opts.on("--very-verbose", "-vv", "Enable very verbose output.") { options[:verbosity] = 3 }
    opts.on("--output-dir OUTPUT_DIR", "Directory to write the output JSON files.") { |v| options[:output_dir] = v }

    opts.separator ""
    opts.separator "Note: *{.csv,.tsv,.txt} inputs default to the correct format, but --csv, --tsv, or --txt overrides."
    opts.separator "Any other filename extension is treated like *.txt."
    opts.separator "Note: Default is --header except for *.txt inputs, but --header or --no-header overrides."
  end.parse!

  options[:input_files] = ARGV
  raise OptionParser::MissingArgument, "At least one input file is required." if options[:input_files].empty?
  raise OptionParser::MissingArgument, "--namespace is required." if options[:namespace].nil?
  raise OptionParser::MissingArgument, "--dataset-id is required." if options[:dataset_id].nil?

  options
end

def read_file(input_file, column_arg, delimiter, has_header, is_txt)
  Enumerator.new do |yielder|
    File.open(input_file, 'r') do |file|
      if is_txt
        if has_header
          file.readline  # Read and discard the header line
        end
        file.each_line do |line|
          yielder << line.strip
        end
      else
        csv = CSV.new(file, col_sep: delimiter)
        headers = has_header ? csv.shift : nil

        selected_column = if has_header
                            if column_arg.nil? || is_txt
                              headers.first
                            elsif column_arg =~ /^\d+$/
                              headers[column_arg.to_i - 1]
                            else
                              column_arg
                            end
                          else
                            column_arg&.match?(/^\d+$/) ? column_arg.to_i - 1 : 0
                          end

        if has_header
          raise "Column '#{selected_column}' not found in the headers." unless headers.include?(selected_column)
          selected_index = headers.index(selected_column)
        else
          selected_index = selected_column.to_i
        end

        csv.each do |row|
          value = row[selected_index]
          yielder << value if value
        end
      end
    end
  end.lazy
end

def write_json_files(input_file, identities, output_prefix)
  file_count = 0
  chunk = []
  identities.each do |identity|
    chunk << identity
    if chunk.size >= MAX_IDENTITIES_PER_FILE
      file_count += 1
      output_file = File.join($OUTPUT_DIR, "#{output_prefix}-#{file_count.to_s.rjust(3, '0')}.json")
      write_json_file(output_file, chunk, input_file)
      chunk = []
    end
  end

  if chunk.any?
    file_count += 1
    output_file = File.join($OUTPUT_DIR, "#{output_prefix}-#{file_count.to_s.rjust(3, '0')}.json")
    write_json_file(output_file, chunk, input_file)
  end
end

def write_json_file(output_file, chunk, input_file)
  identities = chunk.map { |identity| { "namespace" => { "code": $NAMESPACE } , "identity" => identity } }
  output_data = {
    "action" => "delete_identity",
    "datasetId" => $DATASET_ID,
    "displayName" => $DISPLAY_NAME || output_file,
    "description" => $DESCRIPTION || "JSON generated from #{input_file} at #{CURRENT_DATE} by csv-to-DI-payload.rb",
    "identities" => identities
  }
  File.open(output_file, 'w') do |jsonfile|
    jsonfile.puts(JSON.pretty_generate(output_data, ascii_only: true))
  end
  puts "Wrote #{output_file}" if verbose
end

def main
  options = parse_args

  $DATASET_ID = options[:dataset_id]
  $NAMESPACE = options[:namespace]
  $DISPLAY_NAME = options[:display_name]
  $DESCRIPTION = options[:description]
  $OUTPUT_DIR = options[:output_dir] || "."
  $VERBOSITY = options[:verbosity] || 1

  options[:input_files].each do |input_file|
    puts "Processing file: #{input_file}" if normal_verbosity

    output_prefix = File.basename(input_file, File.extname(input_file))

    format = options[:format] || case File.extname(input_file).downcase
                                 when '.txt' then :txt
                                 when '.tsv' then :tsv
                                 when '.csv' then :csv
                                 else :txt
                                 end

    header = options[:header] || (format != :txt)

    delimiter = case format
                when :txt then nil
                when :tsv then "\t"
                else ','
                end

    is_txt = format == :txt
    identities = read_file(input_file, options[:column], delimiter, header, is_txt)
    write_json_files(input_file, identities, output_prefix)
  end
end

main if __FILE__ == $PROGRAM_NAME
