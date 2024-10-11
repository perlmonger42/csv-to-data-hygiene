CSV-to-Data-Hygiene
========================================================================

The scripts in this repository are intended to make it easier for users of
Adobe's Advanced Data Lifecyle Management service to create identity-delete
work orders.

These scripts take as input CSV, TSV, or TXT files containing primary
identifiers. They generate JSON files in the format expected by ADLM
for identity-delete requests.

Once you have created a JSON file using `cvs-to-DI-payload.py`, you can use it
to create a Work Order: just POST it to the workorder-creation endpoint.

For example, if you've named your generated payload file `My-Deletes.json`:

```bash
    curl --silent --show-error \
         --request POST "https://platform.adobe.io/data/core/hygiene/workorder" \
         --header 'Content-Type: application/json' \
         --header "x-gw-ims-org-id: $YOUR_ADOBE_IMS_ORG_ID" \
         --header "x-api-key: $YOUR_ADOBE_API_KEY" \
         --header "x-sandbox-name: $YOUR_ADOBE_SANDBOX_NAME" \
         --header "Authorization: Bearer $YOUR_ADOBE_ACCESS_TOKEN" \
         --data @My-Deletes.json
```


CSV-to-DI-payload Scripts
========================================================================

The `csv-to-DI-payload.*` script is available in both Python and Ruby.

The namespace of your extracted identifiers must be specified on the
command-line (e.g.  `--namespace email`). The ID of the dataset to be targeted
is also a required option (e.g. `--dataset-id 66f4161cc19b0f2aef3edf10`).

By default, the scripts infer input file format from the filename extension.
However, that can be overridden via the `--csv`, `--tsv`, or `--txt` command-line
option. Unrecognized filename extensions are treated as TXT format.

The TXT format does not support field splitting nor special-character escapes. Each
input line is exactly the identifier as it will be used. I.e., this input line,
which contains double-quote, comma, and TAB characters:

    "stuff and nonsense":	uno, dos, tres, catorce

will cause JSON to be generated that looks like this:

```json
    {
      "action": "delete_identity",
      "datasetId": "66f4161cc19b0f2aef3edf10",
      "displayName": "output/sample-TXT-001.json",
      "description": "a simple sample",
      "identities": [
        {
          "namespace": "email",
          "identity":  "\"stuff and nonsense\":\tuno, dos, tres, catorce"
        },
        ...
      ]
    }
```
...where the `"identity"` field contains all those double-quotes, commas, and
TAB characters.  Note that TSV and CSV input formats would cause the scripts to
treat that input very differently.

By default, the scripts assume that input files have a header line.
I.e., line one defines the field names, and the actual data starts on line two.
However, TXT files default to `--no-header` (but can be overridden with `--header`).

The input column that defines the identities to be deleted is selected via
`--column MyName` (where MyName is defined by the header) or `--column 2`
(1-based index).  The latter form *must* be used for headerless input, and may be
used for either. Any `--column` argument is ignored for TXT input.


Contents of this Repository
========================================================================

The scripts themselves are `csv-to-DI-payload.py` and `csv-to-DI-payload.rb`.

The `sample` directory contains some sample inputs. They give examples of how
to escape special characters like TAB, comma, and double-quotes.

The `expect` directory contains the output that should be generated from the
sample inputs.

The `test-python.sh` and `test-ruby.sh` scripts use the content of the `sample`
and `expect` directories to check that the JSON-generator scripts produce the
expected output.


Usage
========================================================================

Python
------------------------------------------------------------------------
`csv-to-DI-payload.py --help` produces:

    usage: csv-to-DI-payload.py [-h] [--column COLUMN] --namespace NAMESPACE --dataset-id DATASET_ID
                                [--display-name DISPLAY_NAME] [--description DESCRIPTION] [--csv] [--tsv] [--txt]
                                [--header] [--no-header] [--verbose] [--output-dir OUTPUT_DIR]
                                input_file [input_file ...]

    Convert TSV/CSV columns of identities to JSON files for creating ADLS work orders.

    positional arguments:
      input_file            Input TSV/CSV files.

    options:
      -h, --help            show this help message and exit
      --column COLUMN       Column index (1-based) or name. Defaults to the first column.
      --namespace NAMESPACE
                            Namespace value for each identity (e.g., 'email' or 'ECID').
      --dataset-id DATASET_ID
                            ID of dataset to be targeted, or 'ALL'.
      --display-name DISPLAY_NAME
                            Display name for the work order.
      --description DESCRIPTION
                            Description for the work order.
      --csv                 Force input files to be read as CSV.
      --tsv                 Force input files to be read as TSV.
      --txt                 Force input files to be read as TXT.
      --header              Indicate that the input files have headers.
      --no-header           Indicate that line 1 of input files is data.
      --verbose, -v         Enable verbose output.
      --output-dir OUTPUT_DIR
                            Directory to write the output JSON files.

    Note: *.csv, *.tsv, and *.txt inputs default to the correct format, but --csv, --tsv, or --txt overrides. Default is
    --header except for *.txt inputs, but --header or --no-header overrides.


Ruby
------------------------------------------------------------------------

`csv-to-DI-payload.rb --help` produces:

    Usage: csv-to-DI-payload.rb [options] input_file1 [input_file2 ...]
            --column COLUMN              Column index (1-based) or name. Defaults to the first column.
            --namespace NAMESPACE        Namespace value for each identity (e.g., 'email' or 'ECID').
            --dataset-id DATASET_ID      ID of dataset to be targeted, or 'ALL'.
            --display-name DISPLAY_NAME  Display name for the work order.
            --description DESCRIPTION    Description for the work order.
            --csv                        Force input files to be read as CSV.
            --tsv                        Force input files to be read as TSV.
            --txt                        Force input files to be read as TXT.
            --[no-]header                Indicate whether the input files have headers (default true except for txt)
        -v, --verbose                    Enable verbose output.
            --output-dir OUTPUT_DIR      Directory to write the output JSON files.

    Note: *{.csv,.tsv,.txt} inputs default to the correct format, but --csv, --tsv, or --txt overrides.
    Note: Default is --header except for *.txt inputs, but --header or --no-header overrides.
