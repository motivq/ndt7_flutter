#!/usr/bin/env bash

# This script produces a "tree-like" project layout including both
# directories and files, honoring .gitignore.

set -euo pipefail

OUTPUT_FILE="project_layout.txt"
echo "Generating project layout into '$OUTPUT_FILE'..."

# Move to the Git project root
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

# Clear/create the output file
> "$OUTPUT_FILE"

###############################################################################
# STEP 1: Collect all non-ignored files
###############################################################################
# "git ls-files --exclude-standard --others --cached" finds:
#   - tracked files
#   - untracked files (that aren't in .gitignore)
#   - but not ignored files
FILES="$(git ls-files --exclude-standard --others --cached)"

###############################################################################
# STEP 2: Record which paths are actual files vs. directories.
#         We'll build a set of file paths in an associative array for quick lookup.
###############################################################################
declare -A IS_FILE
# Populate IS_FILE["some/path/file.go"]=1 for each real file
while IFS= read -r file; do
  IS_FILE["$file"]=1
done <<< "$FILES"

###############################################################################
# STEP 3: Generate a combined list of directories + files
#
#   - For each file path "dir/subdir/file.ext", we split on '/' and emit:
#       dir
#       dir/subdir
#       dir/subdir/file.ext
#     so that directories show up too.
#   - Then we sort and unique them, so each directory appears exactly once.
###############################################################################
{
  while IFS= read -r file; do
    # Split the file path into segments
    IFS='/' read -ra parts <<< "$file"

    # Build up each subdirectory in turn
    local_path=""
    for (( i=0; i<${#parts[@]}-1; i++ )); do
      local_path="$local_path${local_path:+/}${parts[i]}"
      echo "$local_path"
    done

    # Finally emit the full file path itself
    echo "$file"
  done <<< "$FILES"
} \
| sort -u \
| while IFS= read -r item; do
  # 'item' may be a directory (like "dir/subdir") or a file ("dir/sub/file.go")

  # Count how many slashes to determine indentation level
  indent_count=$(echo "$item" | tr -cd '/' | wc -c)
  # Multiply by 2 spaces
  padding=$(printf '%*s' "$((indent_count * 2))" '')

  # We'll display only the basename (final segment)
  # e.g. item="dir/subdir" => name="subdir"
  #      item="dir/sub/file.go" => name="file.go"
  name=$(basename "$item")

  # For clarity, you might also want to differentiate directories vs files,
  # e.g. by appending a slash to directories. If so, do:
  # if [[ -z "${IS_FILE[$item]:-}" ]]; then
  #   name="$name/"  # Mark directories
  # fi

  echo "${padding}${name}" >> "$OUTPUT_FILE"
done

echo "Done! See '$OUTPUT_FILE' for project layout."
