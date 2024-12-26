#!/bin/bash

set -e

# Logs an error message in GitHub Actions format, and exits the script with
# a non-zero status code.
# @param {string} message - The error message to log.
log_fatal() {
  local message="$1"
  echo "::error::$message"
  exit 1
}

# Logs a notice message in GitHub Actions format.
# @param {string} message - The notice message to log.
log_info() {
  local message="$1"
  echo "::notice::$message"
}

# Logs a debug message in GitHub Actions format.
# @param {string} message - The debug message to log.
log_debug() {
  local message="$1"
  echo "::debug::$message"
}

# Checks if yq is installed and is version 4.
check_yq_version() {
  if ! command -v yq &> /dev/null; then
    log_fatal "yq is not installed. please install yq version >4."
  fi

  local version
  version=$(yq --version | awk '{print $3}')
  if [[ $(echo -e "$version\n4" | sort -V | head -n1) != "4" ]]; then
    log_fatal "yq version must be greater than 4. found version: $version"
  fi

  log_info "yq version $version is valid."
}

# Normalize input into an array by splitting on newlines or commas.
# @param {string} input - The input string to normalize.
# @param {string} output_array_name - The name of the output array.
normalize_input() {
    local input="$1"
    local output_array_name="$2"

    if [[ -z "$input" ]]; then
        eval "$output_array_name=()"
        return
    fi

    local IFS=$'\n'
    local normalized_input
    normalized_input=$(echo "$input" | tr '\n' ',')

    IFS=',' read -r -a output_array <<< "$normalized_input"

    eval "$output_array_name=(\"\${output_array[@]}\")"
}

# Validates the inputs passed to the action.
# files and expressions must be specified together, or file_expressions must be specified.
# files must exist.
# @param {string} files - The files to patch/query exists.
# @param {string} expressions - The yq expressions to patch/query.
# @param {string} file_expressions - The file expressions to patch/query.
validate_inputs() {
  local -r -a files=("${!1}")
  local -r -a expressions=("${!2}")
  local -r -a file_expressions=("${!3}")

  if [[ -z "$file_expressions" && (-z "$files" || -z "$expressions") ]]; then
    log_fatal "either 'files' and 'expressions' must be specified together, or 'file-expressions' must be specified."
  fi

  local all_files=("${files[@]}")
  if [[ -n "$file_expressions" ]]; then
    for fe in "${file_expressions[@]}"; do
      local file="${fe%%:*}"
      all_files+=("$file")
    done
  fi

  for file in "${all_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      log_fatal "file does not exist: $file"
    fi
  done

  log_info "inputs validated successfully."
}

# Processes a single file with the given expressions.
# @param {string} file - The file to process.
# @param {array} expressions - Comma-separated yq expressions to patch the file with.
process_file() {
  local file="$1"
  local expressions_string="$2"
  local IFS=','

  # Split the expressions string into an array
  read -r -a expr_array <<< "$expressions_string"

  # Validate the YAML file syntax
  if ! yq eval '.' "$file" > /dev/null 2>&1; then
    log_fatal "invalid syntax in file: $file"
  fi

  for expression in "${expr_array[@]}"; do
    log_info "processing file: $file with expression: $expression"
    if ! yq eval "$expression" -i "$file"; then
      log_fatal "failed to process file: $file with expression: $expression"
    fi
  done
}

# Processes all files with the given expressions.
# It aggregates the expressions to process the files with.
# @param {string} files - The files to process.
# @param {string} expressions - The yq expressions to process the files with.
# @param {string} file_expressions - The file expressions to process the files with.
process_files() {
  local -r -a files=("${!1}")
  local -r -a expressions=("${!2}")
  local -r -a file_expressions=("${!3}")

  # Declare an associative array to map files to their expressions as arrays
  declare -A file_to_expressions

  # Add global expressions to all files
  for file in "${files[@]}"; do
    file_to_expressions["$file"]="${expressions[*]}"
  done

  # Add file-specific expressions
  for fe in "${file_expressions[@]}"; do
    local file="${fe%%:*}"
    local expression="${fe#*:}"
    if [[ -n "${file_to_expressions[$file]}" ]]; then
      file_to_expressions["$file"]+=",${expression}"
    else
      file_to_expressions["$file"]="$expression"
    fi
  done

  for file in "${!file_to_expressions[@]}"; do
    IFS=',' read -r -a expressions_array <<< "${file_to_expressions[$file]}"
    process_file "$file" "${expressions_array[@]}"
  done
}

main(){
  check_yq_version

  files=()
  expressions=()
  file_expressions=()
  all_files=()

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          --files)
              normalize_input "$2" files
              shift 2
              ;;
          --expressions)
              normalize_input "$2" expressions
              shift 2
              ;;
          --file-expressions)
              normalize_input "$2" file_expressions
              shift 2
              ;;
          *) log_fatal "unknown parameter passed: $1" ;;
      esac
  done

  log_debug "files: ${files[*]}"
  log_debug "expressions: ${expressions[*]}"
  log_debug "file_expressions: ${file_expressions[*]}"

  validate_inputs files[@] expressions[@] file_expressions[@]
  process_files files[@] expressions[@] file_expressions[@]
}

main "$@"