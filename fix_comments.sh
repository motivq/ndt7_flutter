#!/opt/homebrew/bin/bash

set -uo pipefail

# -----------------------------------------------------------------------------
# Determine if we're on macOS vs. Linux/other, for sed differences
# -----------------------------------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
  # Using BSD sed with "-i ''" (no backup extension)
  SED_CMD=(sed -i '')
  IS_BSD_SED=true
else
  # Usually GNU sed or compatible
  SED_CMD=(sed -i)
  IS_BSD_SED=false
fi

# -----------------------------------------------------------------------------
# Associative arrays for prefix & suffix by extension
# -----------------------------------------------------------------------------
declare -A COMMENT_PREFIX=(
  [go]="//"
  [proto]="//"
  [dart]="//"
  [sql]="--"
  [yml]="#"
  [yaml]="#"
  [html]="<!--"
)

# If an extension isn’t listed here, it implies no suffix is needed.
declare -A COMMENT_SUFFIX=(
  [html]="-->"
)

# -----------------------------------------------------------------------------
# Fallback for empty files
#   - If the file has zero non-empty lines, just overwrite with the expected_line.
# -----------------------------------------------------------------------------
fallback_for_empty_file() {
  local file="$1"
  local text="$2"
  echo "File '$file' is empty. Writing single comment line directly..."
  echo "$text" > "$file"
}

# -----------------------------------------------------------------------------
# Prepend a line to a file (non-empty). We do a multiline approach for BSD sed
# to insert a real newline, and a simpler approach for GNU sed.
#
# We use '|' as the sed delimiter because '#' might appear in the text (e.g. .yaml).
# -----------------------------------------------------------------------------
prepend_line() {
  local file="$1"
  local text="$2"

  echo "DEBUG: Prepending line to file '$file' with text '$text'"

  if [[ "$IS_BSD_SED" == true ]]; then
    # BSD sed: multiline insertion
    "${SED_CMD[@]}" -e "1s|^|${text}\\
|" "$file"
  else
    # GNU sed: can handle \n
    "${SED_CMD[@]}" "1s|^|${text}\n|" "$file"
  fi
}

# -----------------------------------------------------------------------------
# Replace a specific line number's content entirely.
# -----------------------------------------------------------------------------
replace_line() {
  local file="$1"
  local line_number="$2"
  local new_text="$3"
  echo "DEBUG: Replacing line $line_number in file '$file' with '$new_text'"
  # Also use '|' as the delimiter
  "${SED_CMD[@]}" "${line_number}s|.*|${new_text}|" "$file"
}

# -----------------------------------------------------------------------------
# fix_comment_line <file> <rel_path> <prefix> <suffix>
#   - Ensures the first *non-empty* line is the correct comment (PREFIX + rel_path [+ SUFFIX]).
#   - If file is empty, we write the comment. If first line is a different comment, we prepend.
# -----------------------------------------------------------------------------
fix_comment_line() {
  local file="$1"
  local rel_path="$2"
  local prefix="$3"
  local suffix="$4"

  # If prefix is empty, extension not supported
  if [[ -z "$prefix" ]]; then
    return 0
  fi

  local expected_line="${prefix} ${rel_path}"
  [[ -n "$suffix" ]] && expected_line="${prefix} ${rel_path} ${suffix}"

  # Find first non-empty line
  local first_line_num first_line
  read -r first_line_num first_line < <(
    awk 'NF {print NR, $0; exit}' "$file" 2>/dev/null || true
  )

  # If there's no non-empty line, the file is empty or whitespace only
  if [[ -z "$first_line_num" ]]; then
    echo "Prepending comment to empty file: $file"
    fallback_for_empty_file "$file" "$expected_line"
    return 0
  fi

  # If first non-empty line starts with the correct prefix
  if [[ "$first_line" == "$prefix "* ]]; then
    # It's a comment line. Check if correct.
    if [[ "$first_line" != "$expected_line" ]]; then
      echo "Updating comment in file: $file"
      replace_line "$file" "$first_line_num" "$expected_line"
    else
      echo "Comment already correct in file: $file"
    fi
  else
    # The first non-empty line is not our comment. Prepend.
    echo "Prepending comment in file: $file (first non-empty line was not comment)"
    prepend_line "$file" "$expected_line"
  fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

# List non-ignored (tracked + untracked) files
FILES="$(git ls-files --exclude-standard --others --cached)"
echo "DEBUG: Files from git ls-files:"
echo "$FILES" | nl

while IFS= read -r file; do
  # Skip directories
  [[ -d "$file" ]] && continue

  echo "DEBUG: Checking extension for '$file'"
  ext="${file##*.}"
  echo "DEBUG:   Extracted extension '$ext'"

  # Retrieve prefix & suffix from our associative arrays
  prefix="${COMMENT_PREFIX[$ext]:-}"
  suffix="${COMMENT_SUFFIX[$ext]:-}"

  # If there's a prefix for this extension, we process it:
  if [[ -n "$prefix" ]]; then
    echo "Checking file: $file"
    fix_comment_line "$file" "$file" "$prefix" "$suffix"
  fi

done <<< "$FILES"
