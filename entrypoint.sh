#!/bin/bash

set -e

# Logging Functions

# Logs an error message in GitHub Actions format.
# @param {string} message - The error message to log.
log_error() {
  local message="$1"
  echo "::error::$message"
}

# Logs a notice message in GitHub Actions format.
# @param {string} message - The notice message to log.
log_notice() {
  local message="$1"
  echo "::notice::$message"
}

# Logs a debug message in GitHub Actions format.
# @param {string} message - The debug message to log.
log_debug() {
  local message="$1"
  echo "::debug::$message"
}

# Schema Validation

# Validates the inputs against the expected schema.
# Ensures the required inputs are provided and formatted correctly.
# Logs errors and exits if validation fails.
validate_schema() {
  log_debug "validating input schema..."

  if [ -z "$MODE" ]; then
    log_error "'mode' input is required."
    exit 1
  fi

  if [[ "$MODE" != "patch" && "$MODE" != "query" ]]; then
    log_error "'mode' must be either 'patch' or 'query'."
    exit 1
  fi

  if [ -z "$FILES" ] && [ -z "$FILE_EXPRESSIONS" ]; then
    log_error "at least one of 'files' or 'file-expressions' must be provided."
    exit 1
  fi

  log_debug "schema validation passed."
}

# File Validation

# Validates the provided files to ensure they exist and are readable.
# Logs errors and exits if any file is invalid.
validate_files() {
  log_debug "validating files..."

  if [ -n "$FILES" ]; then
    for FILE in "${FILE_LIST[@]}"; do
      if [ ! -f "$FILE" ]; then
        log_error "file '$FILE' does not exist or is not a valid file."
        exit 1
      fi
      log_debug "file '$FILE' is valid."
    done
  fi

  log_debug "file validation passed."
}

# Process a Single File

# Processes a single file with the given expressions and mode.
# For 'query' mode, retrieves values based on the expressions.
# For 'patch' mode, modifies the file in place based on the expressions.
# @param {string} file - The file to process.
# @param {string} expressions - The expressions to apply.
# @param {string} mode - The mode to use (either "patch" or "query").
# @returns {string} The result of processing the file in JSON format.
process_file() {
  local file="$1"
  local expressions="$2"
  local mode="$3"
  local file_result="{}"

  IFS=',' read -ra EXP_LIST <<< "$expressions"
  for EXP in "${EXP_LIST[@]}"; do
    if [ "$mode" = "query" ]; then
      log_debug "querying file '$file' with expression '$EXP'."
      RESULT=$(yq eval "$EXP" "$file" 2>&1) || {
        log_error "failed to query expression '$EXP' in file '$file': $RESULT"
        exit 1
      }
      file_result=$(echo "$file_result" | yq eval ".\"$EXP\" = \"$RESULT\"" -)
    else
      log_debug "patching file '$file' with expression '$EXP'."
      yq eval "$EXP" -i "$file" 2>&1 || {
        log_error "failed to apply expression '$EXP' to file '$file'"
        exit 1
      }
    fi
  done

  echo "$file_result"
}

# Process Files and Generate Output

# Processes the provided files and generates output.
# Iterates over each file and applies the appropriate expressions based on the mode.
# @returns {string} The result of processing the files in JSON format.
process_files() {
  log_debug "processing files..."
  RESULT_JSON="{}"

  # Process each file
  for FILE in "${FILE_LIST[@]}"; do
    expressions="$EXPRESSIONS"

    # Check for file-specific expressions
    for FILE_EXP in "${FILE_EXP_LIST[@]}"; do
      FILE_NAME=$(echo "$FILE_EXP" | cut -d':' -f1)
      if [ "$FILE_NAME" = "$FILE" ]; then
        expressions=$(echo "$FILE_EXP" | cut -d':' -f2)
        break
      fi
    done

    # Skip if no expressions are found
    if [ -z "$expressions" ]; then
      log_notice "no expressions found for file '$FILE'. skipping."
      continue
    fi

    log_notice "processing file '$FILE' with expressions: $expressions"
    FILE_RESULT=$(process_file "$FILE" "$expressions" "$MODE")
    if [ "$MODE" = "query" ]; then
      RESULT_JSON=$(echo "$RESULT_JSON" | yq eval ".\"$FILE\" = $FILE_RESULT" -)
    fi
  done

  echo "$RESULT_JSON"
}

# Main Execution

# Main function to execute the script.
# Parses inputs, validates them, processes files, and outputs results.
main() {
  # Parse inputs
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2;;
      --files) FILES="$2"; shift 2;;
      --expressions) EXPRESSIONS="$2"; shift 2;;
      --file-expressions) FILE_EXPRESSIONS="$2"; shift 2;;
      *) log_error "unknown parameter passed: $1"; exit 1;;
    esac
  done

  # Initialize arrays
  IFS=',' read -ra FILE_LIST <<< "$FILES"
  IFS=',' read -ra GLOBAL_EXP_LIST <<< "$EXPRESSIONS"
  IFS=',' read -ra FILE_EXP_LIST <<< "$FILE_EXPRESSIONS"

  # Validate inputs
  validate_schema
  validate_files

  # Process files
  RESULT=$(process_files)

  # Output results
  if [ "$MODE" = "query" ]; then
    echo "query-output=$RESULT" >> $GITHUB_OUTPUT
  else
    log_notice "patch mode completed. returning empty output."
    echo "query-output={}" >> $GITHUB_OUTPUT
  fi
}

main "$@"
