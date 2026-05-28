#!/usr/bin/env bash
# convert.sh — Convert .swf files to the Gams Ruffle format.
#
# Usage:
#   ./convert.sh file1.swf [file2.swf ...]      # explicit file list
#   ./convert.sh --dir ./some-folder             # recurse a folder for .swf files
#
# Output per game:
#   g/g/Ruffle/swfs/<name>.js          (single-file, < 20 MB base64)
#   g/g/Ruffle/swfs/<name>/data1.js    (multi-part, >= 20 MB base64)
#   g/g/Ruffle/swfs/<name>/data2.js
#   g/<name>.html                      (wrapper)
#
# Then add each game to the gamsList array in Gams.html.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SWF_DIR="$REPO_ROOT/g/g/Ruffle/swfs"
WRAPPER_DIR="$REPO_ROOT/g"
SINGLE_TEMPLATE="$SWF_DIR/single_game.html"
SPLIT_TEMPLATE="$SWF_DIR/split_game.html"

# Split base64 data URL into ~20 MB chunks
# The base64 text is what gets stored in the .js files (not the raw SWF).
# 20 MB = 20*1024*1024 = 20971520 bytes of text output.
SPLIT_SIZE=$((20 * 1024 * 1024))

convert_one() {
  local swf_path="$1"

  if [[ ! -f "$swf_path" ]]; then
    echo "ERROR: File not found: $swf_path" >&2
    return 1
  fi

  local basename
  basename="$(basename "$swf_path" .swf)"
  # Slugify: lowercase, replace spaces/special chars with nothing
  local name
  name="$(echo "$basename" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9')"

  echo "=== Converting: $basename ==="

  # Base64-encode the SWF into a data URL (no line wrapping)
  local data_url="data:application/vnd.adobe.flash.movie;base64,"
  local b64
  b64="$(base64 -w0 "$swf_path")"

  # Check total base64 text length to decide single vs split
  local b64_len=${#b64}

  if (( b64_len > SPLIT_SIZE )); then
    # --- MULTI-PART ---
    local dir="$SWF_DIR/$name"
    mkdir -p "$dir"

    echo "  Size: ${b64_len} bytes base64 → splitting into parts"

    # Split the base64 string into chunks using dd
    local chunk=1
    local offset=0
    while (( offset < b64_len )); do
      local remaining=$((b64_len - offset))
      local this_chunk=$SPLIT_SIZE
      if (( remaining < this_chunk )); then
        this_chunk=$remaining
      fi
      local chunk_b64="${b64:offset:this_chunk}"
      echo "window.data${chunk}='${data_url}${chunk_b64}';" > "$dir/data${chunk}.js"
      echo "  Written: data${chunk}.js ($(wc -c < "$dir/data${chunk}.js") bytes)"
      offset=$((offset + this_chunk))
      chunk=$((chunk + 1))
    done

    # Write wrapper using split template
    local wrapper="$WRAPPER_DIR/$name.html"
    cp "$SPLIT_TEMPLATE" "$wrapper"
    sed -i "s|SWF_PLACEHOLDER|g/Ruffle/swfs/$name|g" "$wrapper"

  else
    # --- SINGLE FILE ---
    echo "  Size: ${b64_len} bytes base64 → single file"

    echo "window.data='${data_url}${b64}';" > "$SWF_DIR/$name.js"
    echo "  Written: $name.js ($(wc -c < "$SWF_DIR/$name.js") bytes)"

    # Write wrapper using single template
    local wrapper="$WRAPPER_DIR/$name.html"
    cp "$SINGLE_TEMPLATE" "$wrapper"
    sed -i "s|SWF_PLACEHOLDER|g/Ruffle/swfs/$name.js|g" "$wrapper"
  fi

  echo "  Wrapper: $wrapper"
  echo ""
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 file1.swf [file2.swf ...]" >&2
  echo "       $0 --dir ./some-folder" >&2
  exit 1
fi

# Collect SWF files from arguments (files or --dir)
swf_files=()

if [[ "$1" == "--dir" ]]; then
  dir_arg="$2"
  if [[ ! -d "$dir_arg" ]]; then
    echo "ERROR: Directory not found: $dir_arg" >&2
    exit 1
  fi
  echo "Scanning directory: $dir_arg"
  while IFS= read -r -d '' f; do
    swf_files+=("$f")
  done < <(find "$dir_arg" -name '*.swf' -type f -print0 | sort -z)
  echo "Found ${#swf_files[@]} SWF file(s)."
  shift 2
else
  swf_files=("$@")
fi

for swf in "${swf_files[@]}"; do
  convert_one "$swf"
done

echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Add each new game to the gamsList array in Gams.html"
echo "  2. Optionally add a thumbnail: img/<slug>.png"
