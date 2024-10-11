#!/usr/bin/env python3
import argparse
import csv
import datetime
import json
import os
import sys

MAX_IDENTITIES_PER_FILE = 100000
CURRENT_DATE = datetime.datetime.now().isoformat()

# Values from the Command-line
DATASET_ID = None
NAMESPACE = None
DISPLAY_NAME = None
DESCRIPTION = None
OUTPUT_DIR = "."
VERBOSE = False

def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert TSV/CSV columns of identities to JSON files for creating ADLS work orders.",
        epilog="Note: *.csv, *.tsv, and *.txt inputs default to the correct format, but --csv, --tsv, or --txt overrides." +
               " Default is --header except for *.txt inputs, but --header or --no-header overrides."
    )
    parser.add_argument('input_file', nargs='+', help="Input TSV/CSV files.")
    parser.add_argument('--column', help="Column index (1-based) or name. Defaults to the first column.", default=None)
    parser.add_argument('--namespace', required=True, help="Namespace value for each identity (e.g., 'email' or 'ECID').")
    parser.add_argument('--dataset-id', required=True, help="ID of dataset to be targeted, or 'ALL'.")
    parser.add_argument('--display-name', help="Display name for the work order.", default=None)
    parser.add_argument('--description', help="Description for the work order.", default=None)
    parser.add_argument('--csv', action='store_true', help="Force input files to be read as CSV.")
    parser.add_argument('--tsv', action='store_true', help="Force input files to be read as TSV.")
    parser.add_argument('--txt', action='store_true', help="Force input files to be read as TXT.")
    parser.add_argument('--header', dest='header', action='store_true', help="Indicate that the input files have headers.")
    parser.add_argument('--no-header', dest='header', action='store_false', help="Indicate that line 1 of input files is data.")
    parser.add_argument('--verbose', '-v', action='store_true', help="Enable verbose output.")
    parser.add_argument('--output-dir', help="Directory to write the output JSON files.", default='.')
    parser.set_defaults(header=None)
    return parser.parse_args()

def read_file(input_file, column_arg, delimiter, has_header, is_txt):
    with open(input_file, 'r', newline='') as file:
        if is_txt:
            if has_header:
                next(file)  # Skip the header line
            for line in file:
                yield line.strip()
        elif has_header:
            reader = csv.DictReader(file, delimiter=delimiter)
            headers = reader.fieldnames

            if column_arg is None:
                selected_column = headers[0]  # default to first column
            elif column_arg.isdigit():
                col_idx = int(column_arg) - 1  # 1-based index
                selected_column = headers[col_idx]
            else:
                selected_column = column_arg
                if selected_column not in headers:
                    raise ValueError(f"Column '{selected_column}' not found in the headers.")

            for row in reader:
                yield row[selected_column]
        else:
            reader = csv.reader(file, delimiter=delimiter, quotechar='"', quoting=csv.QUOTE_MINIMAL)
            col_idx = int(column_arg) - 1 if column_arg and column_arg.isdigit() else 0

            for row in reader:
                yield row[col_idx]

def write_json_files(input_file, identities, output_prefix):
    file_count = 0
    chunk = []
    for identity in identities:
        chunk.append(identity)
        if len(chunk) >= MAX_IDENTITIES_PER_FILE:
            file_count += 1
            output_file = os.path.join(OUTPUT_DIR, f"{output_prefix}-{file_count:03d}.json")
            write_json_file(output_file, chunk, input_file)
            chunk = []

    if chunk:
        file_count += 1
        output_file = os.path.join(OUTPUT_DIR, f"{output_prefix}-{file_count:03d}.json")
        write_json_file(output_file, chunk, input_file)

def write_json_file(output_file, chunk, input_file):
    identities = [{"namespace": NAMESPACE, "identity": identity} for identity in chunk]
    output_data = {
        "action": "delete_identity",
        "datasetId": DATASET_ID,
        "displayName": DISPLAY_NAME or output_file,
        "description": DESCRIPTION or f"JSON generated from {input_file} at {CURRENT_DATE} by csv-to-DI-payload.py",
        "identities": identities
    }
    with open(output_file, 'w') as jsonfile:
        json.dump(output_data, jsonfile, indent=2)
        jsonfile.write('\n')  # Ensure terminal newline
    if VERBOSE:
        print(f"Wrote {output_file}")

def main():
    global DATASET_ID, NAMESPACE, DISPLAY_NAME, DESCRIPTION, OUTPUT_DIR, VERBOSE

    args = parse_args()

    DATASET_ID = args.dataset_id
    NAMESPACE = args.namespace
    DISPLAY_NAME = args.display_name
    DESCRIPTION = args.description
    OUTPUT_DIR = args.output_dir
    VERBOSE = args.verbose

    for input_file in args.input_file:
        if VERBOSE:
            print(f"Processing file: {input_file}", file=sys.stderr)

        output_prefix = os.path.splitext(os.path.basename(input_file))[0]

        if args.txt:
            delimiter = None
            is_txt = True
        elif args.tsv:
            delimiter = '\t'
            is_txt = False
        elif args.csv:
            delimiter = ','
            is_txt = False
        else:
            extension = os.path.splitext(input_file)[1].lower()
            if extension == '.txt':
                delimiter = None
                is_txt = True
            else:
                delimiter = '\t' if extension == '.tsv' else ','
                is_txt = False

        header = args.header if args.header is not None else not is_txt
        identities = read_file(input_file, args.column, delimiter, header, is_txt)
        write_json_files(input_file, identities, output_prefix)

if __name__ == "__main__":
    main()