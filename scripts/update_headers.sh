#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# List of paths to exclude
EXCLUDED_PATHS=(
    "Pods"
    "Generated"
    ".build"
    "CGMBLEKit"
    "DanaKit"
    "G7SensorKit"
    "LibreTransmitter"
    "LoopKit"
    "MinimedKit"
    "OmniBLE"
    "OmniKit"
    "RileyLinkKit"
    "TidepoolService"
    "dexcom-share-client-swift"
    "Package.swift"
)

# Function to normalize author names
normalize_author() {
    local author="$1"
    case "$author" in
        "polscm32"|"marvout"|"polscm32 aka Marvout")
            echo "Marvin Polscheit"
            ;;
        *)
            echo "$author"
            ;;
    esac
}

# Function to generate the header
generate_header() {
    local filename="$1"
    local creator="$2"
    local creation_date="$3"
    local last_editor="$4"
    local last_edit_date="$5"
    local top_contributor="$6"
    local second_contributor="$7"

    cat << EOF
//
// Trio
// ${filename}
// Created by ${creator} on ${creation_date}.
// Last edited by ${last_editor} on ${last_edit_date}.
// Most contributions by ${top_contributor}${second_contributor:+ and ${second_contributor}}.
//
// Documentation available under: https://triodocs.org/
EOF
}

# Function to check if a file should be excluded
is_excluded() {
    local file_path="$1"
    for excluded in "${EXCLUDED_PATHS[@]}"; do
        if [[ "$file_path" == *"$excluded"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if header needs update
needs_header_update() {
    local file="$1"
    local creator="$2"
    local creation_date="$3"
    local last_editor="$4"
    local last_edit_date="$5"
    local top_contributor="$6"
    local second_contributor="$7"
    
    # Get first 10 lines of the file
    local header=$(head -n 10 "$file")
    
    # Check if all required header lines exist and are correct
    echo "$header" | grep -q "^// Trio$" || return 0
    echo "$header" | grep -q "^// $(basename "$file")$" || return 0
    echo "$header" | grep -q "^// Created by $creator on $creation_date\.$" || return 0
    echo "$header" | grep -q "^// Last edited by $last_editor on $last_edit_date\.$" || return 0
    echo "$header" | grep -q "^// Most contributions by $top_contributor\.$" || return 0
    
    # If we get here, header is correct
    return 1
}

# Function to process a single file
process_file() {
    local file="$1"
    
    # Get Git information
    local creator=$(git log --format='%an' --reverse -- "$file" | head -n 1)
    local creation_date=$(git log --format='%as' --reverse -- "$file" | head -n 1)
    local last_editor=$(git log -1 --format='%an' -- "$file")
    local last_edit_date=$(git log -1 --format='%as' -- "$file")
    
    # Normalize author names
    creator=$(normalize_author "$creator")
    last_editor=$(normalize_author "$last_editor")
    
    # Get first and second unique contributors
    local first_author=""
    local second_author=""
    
    # Process each line to find unique contributors
    while IFS= read -r line; do
        local author=$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
        if [ "$author" != "Not Committed Yet" ] && [ ! -z "$author" ]; then
            local normalized_author=$(normalize_author "$author")
            if [ -z "$first_author" ]; then
                first_author="$normalized_author"
            elif [ "$normalized_author" != "$first_author" ] && [ -z "$second_author" ]; then
                second_author="$normalized_author"
                break
            fi
        fi
    done < <(git blame --line-porcelain "$file" | grep "^author " | cut -d" " -f2- | grep -v "Not Committed Yet" | grep -v "^$" | sort | uniq -c | sort -rn)
    
    local top_contributor="$first_author"
    local second_contributor="$second_author"
    
    # Quick check if header needs update
    if ! needs_header_update "$file" "$creator" "$creation_date" "$last_editor" "$last_edit_date" "$top_contributor" "$second_contributor"; then
        echo -e "${GREEN}✓ Header up to date: $file${NC}"
        return
    fi
    
    # Generate header
    local filename=$(basename "$file")
    local header=$(generate_header "$filename" "$creator" "$creation_date" "$last_editor" "$last_edit_date" "$top_contributor" "$second_contributor")
    
    # Find where the actual content starts (after any existing header)
    local content_start=$(awk '!(/^\/\/|^$/) {print NR; exit}' "$file")
    if [ -z "$content_start" ]; then
        content_start=1
    fi
    
    # Extract content without header
    local content=$(tail -n +$content_start "$file")
    
    # Write new header and content
    echo "$header" > "$file"
    echo "" >> "$file"
    echo "$content" >> "$file"
    
    echo -e "${GREEN}✅ Updated header for: $file${NC}"
}

# Function to get modified Swift files
get_modified_files() {
    # Get both staged and unstaged changes
    git status --porcelain | grep "\.swift$" | awk '{print $2}'
}

# Main function
main() {
    # Change to git root directory
    cd "$(git rev-parse --show-toplevel)" || exit 1
    
    echo "🔍 Searching for Swift files..."
    
    # Process only modified Swift files
    while IFS= read -r file; do
        if [ -n "$file" ] && ! is_excluded "$file"; then
            process_file "$file"
        fi
    done < <(get_modified_files)
    
    echo -e "${GREEN}✨ Done!${NC}"
}

# Run the script
main

