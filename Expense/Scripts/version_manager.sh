#!/bin/bash

# Function to increment version
increment_version() {
    local version=$1
    local position=$2
    
    IFS='.' read -ra ADDR <<< "$version"
    if [ "${#ADDR[@]}" -ne 3 ]; then
        echo "Invalid version format. Use x.y.z"
        exit 1
    fi
    
    case $position in
        "major")
            ADDR[0]=$((ADDR[0] + 1))
            ADDR[1]=0
            ADDR[2]=0
            ;;
        "minor")
            ADDR[1]=$((ADDR[1] + 1))
            ADDR[2]=0
            ;;
        "patch")
            ADDR[2]=$((ADDR[2] + 1))
            ;;
        *)
            echo "Invalid position. Use major, minor, or patch"
            exit 1
            ;;
    esac
    
    echo "${ADDR[0]}.${ADDR[1]}.${ADDR[2]}"
}

# Function to update version
update_version() {
    local position=$1
    local current_version=$(agvtool what-marketing-version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "1.0.0")
    local new_version=$(increment_version "$current_version" "$position")
    
    echo "Updating version from $current_version to $new_version"
    agvtool new-marketing-version "$new_version"
    agvtool next-version -all
}

# Main script
case "$1" in
    "major"|"minor"|"patch")
        update_version "$1"
        ;;
    *)
        echo "Usage: $0 {major|minor|patch}"
        echo "  major: Breaking changes (x.0.0)"
        echo "  minor: New features (0.x.0)"
        echo "  patch: Bug fixes (0.0.x)"
        exit 1
        ;;
esac 