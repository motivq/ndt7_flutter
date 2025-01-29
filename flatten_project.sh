#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# CONFIG: Define the file extensions to include
#   You can easily add more entries here as needed.
###############################################################################
declare -A SUPPORTED_EXTENSIONS=(
  [go]=1
  [proto]=1
  [dart]=1
  [sql]=1
  [yml]=1
  [yaml]=1
  [html]=1
)

###############################################################################
# MAIN
###############################################################################
# Determine the project root via Git, then cd there.
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

# We'll write everything into this file:
OUTPUT_FILE="flattened_project.txt"

echo "Flattening project into '$OUTPUT_FILE'..."
# Overwrite any existing file:
> "$OUTPUT_FILE"

# Create a temporary file to store all content
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

# Process each file
while IFS= read -r file; do
  # Skip directories
  if [[ -d "$file" ]]; then
    continue
  fi

  # Extract the extension
  ext="${file##*.}"

  # Check if this extension is in our associative array
  if [[ -n "${SUPPORTED_EXTENSIONS[$ext]:-}" ]]; then
    echo "Adding '$file'..."
    echo "=== START: $file ===" >> "$TEMP_FILE"
    cat "$file" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "=== END: $file ===" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
  fi
done < <(git ls-files --exclude-standard --others --cached)

# Copy the temp file to the final output file in one operation
cat "$TEMP_FILE" > "$OUTPUT_FILE"

echo "Done! Flattened output is in '$OUTPUT_FILE'."
