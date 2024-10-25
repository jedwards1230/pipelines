#!/usr/bin/env bash

# Check for required commands
command -v git >/dev/null 2>&1 || { echo >&2 "git is not installed. Aborting."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is not installed. Aborting."; exit 1; }
command -v pip >/dev/null 2>&1 || { echo >&2 "pip is not installed. Aborting."; exit 1; }

PORT="${PORT:-9099}"
HOST="${HOST:-0.0.0.0}"
# Default value for PIPELINES_DIR
PIPELINES_DIR=${PIPELINES_DIR:-./pipelines}
# Default value for DEBUG_PIP
DEBUG_PIP=${DEBUG_PIP:-false}

echo "Starting Open WebUI Pipelines..."
echo ""
echo "Host: $HOST"
echo "Port: $PORT"
echo "Pipelines directory: $PIPELINES_DIR"
echo ""
echo "DEBUG_PIP: $DEBUG_PIP"
echo "PIPELINES_URLS: $PIPELINES_URLS"
echo "PIPELINES_REQUIREMENTS_PATH: $PIPELINES_REQUIREMENTS_PATH"
echo "RESET_PIPELINES_DIR: $RESET_PIPELINES_DIR"
echo ""

# Function to reset pipelines
reset_pipelines_dir() {
  if [ "$RESET_PIPELINES_DIR" = true ]; then
    echo "Resetting pipelines directory: $PIPELINES_DIR"

    # Safety checks to prevent accidental deletion
    if [ -z "$PIPELINES_DIR" ] || [ "$PIPELINES_DIR" = "/" ]; then
      echo "Error: PIPELINES_DIR is not set correctly."
      exit 1
    fi

    # Check if the directory exists
    if [ -d "$PIPELINES_DIR" ]; then
      # Remove the directory completely
      rm -rf "$PIPELINES_DIR"
      echo "All contents in $PIPELINES_DIR have been removed."

      # Optionally recreate the directory if needed
      mkdir -p "$PIPELINES_DIR"
      echo "$PIPELINES_DIR has been recreated."
    else
      echo "Directory $PIPELINES_DIR does not exist. No action taken."
    fi
  else
    echo "RESET_PIPELINES_DIR is not set to true. No action taken."
  fi
}

# Function to install requirements if requirements.txt is provided
install_requirements() {
  local req_file="$1"
  local source="$2"
  if [[ -f "$req_file" ]]; then
    if [ -n "$source" ]; then
      echo "Installing requirements from $source..."
    else
      echo "requirements.txt found at $req_file. Installing requirements..."
    fi
    if [ "$DEBUG_PIP" = true ]; then
      pip install -r "$req_file" || { echo "Failed to install requirements from $source"; exit 1; }
    else
      pip install -r "$req_file" --quiet >/dev/null 2>&1 || { echo "Failed to install requirements from $source"; exit 1; }
    fi
  else
    if [ -n "$source" ]; then
      echo "No requirements found in $source. Skipping installation of requirements."
    else
      echo "requirements.txt not found at $req_file. Skipping installation of requirements."
    fi
  fi
}

# Function to download the pipeline files
download_pipelines() {
  local path="$1"
  local destination="$2"

  # Remove any surrounding quotes from the path
  path=$(echo "$path" | sed 's/^"//;s/"$//')

  echo "Downloading pipeline files from '$path' to '$destination'..."

  if [[ "$path" =~ ^https://github.com/.*/.*/blob/.* ]]; then
    # It's a single file
    dest_file=$(basename "$path")
    raw_url="${path/\/blob\//\/raw\/}"
    curl -L "$raw_url" -o "$destination/$dest_file" || { echo "Failed to download $path"; exit 1; }
  elif [[ "$path" =~ ^https://github.com/.*/.*/tree/.* ]]; then
    # It's a folder
    git_repo=$(echo "$path" | awk -F '/tree/' '{print $1}').git
    after_tree=$(echo "$path" | awk -F '/tree/' '{print $2}')
    branch_name=$(echo "$after_tree" | cut -d'/' -f1)
    subdir=$(echo "$after_tree" | cut -d'/' -f2-)

    temp_dir=$(mktemp -d)
    git clone --depth 1 --filter=blob:none --sparse -b "$branch_name" "$git_repo" "$temp_dir" || { echo "Failed to clone $git_repo"; exit 1; }
    (
      cd "$temp_dir" || exit
      git sparse-checkout init --cone
      git sparse-checkout set "$subdir"
    )
    mkdir -p "$destination"
    mv "$temp_dir/$subdir/"* "$destination/" || { echo "Failed to move files from $temp_dir/$subdir to $destination"; exit 1; }
    rm -rf "$temp_dir"
  elif [[ "$path" =~ ^https://github.com/.*/.*/archive/.*\.zip$ ]]; then
    curl -L "$path" -o "$destination/archive.zip" || { echo "Failed to download $path"; exit 1; }
    unzip "$destination/archive.zip" -d "$destination" || { echo "Failed to unzip archive.zip"; exit 1; }
    rm "$destination/archive.zip"
  elif [[ "$path" =~ \.py$ ]]; then
    # It's a single .py file (but not from GitHub)
    dest_file=$(basename "$path")
    curl -L "$path" -o "$destination/$dest_file" || { echo "Failed to download $path"; exit 1; }
  elif [[ "$path" =~ ^https://github.com/.*/.*$ ]]; then
    # Handle general GitHub repository URL
    git clone "$path" "$destination" || { echo "Failed to clone $path"; exit 1; }
  else
    echo "Invalid URL format: $path"
    exit 1
  fi
}

# Function to parse and install requirements from frontmatter
install_frontmatter_requirements() {
  local file="$1"
  local file_content
  file_content=$(cat "$file")
  # Extract the first triple-quoted block
  local first_block
  first_block=$(echo "$file_content" | awk '/"""/{flag=!flag; if(flag) count++; if(count == 2) {exit}} flag')
  # Find the line containing 'requirements:'
  local requirements_line
  requirements_line=$(echo "$first_block" | grep -i 'requirements:')

  if [ -n "$requirements_line" ]; then
    # Extract and process the requirements list
    local requirements
    requirements=$(echo "$requirements_line" | awk -F': ' '{print $2}' | tr ',' ' ' | tr -d '\r' | xargs)
    echo "Found requirements in frontmatter of $file: $requirements"
    # Create a temporary requirements.txt file
    local temp_requirements_file
    temp_requirements_file=$(mktemp)
    echo "$requirements" | tr ' ' '\n' > "$temp_requirements_file"
    install_requirements "$temp_requirements_file" "$file"
    rm "$temp_requirements_file"
  else
    echo "No requirements found in frontmatter of $file."
  fi
}

# Check if the PIPELINES_REQUIREMENTS_PATH environment variable is set and non-empty
if [[ -n "$PIPELINES_REQUIREMENTS_PATH" ]]; then
  # Install requirements from the specified requirements.txt
  install_requirements "$PIPELINES_REQUIREMENTS_PATH"
else
  echo "PIPELINES_REQUIREMENTS_PATH not specified. Skipping installation of requirements."
fi

# Reset pipelines directory before any download or cloning operations
reset_pipelines_dir

# Check if the PIPELINES_URLS environment variable is set and non-empty
if [[ -n "$PIPELINES_URLS" ]]; then
  # Check if RESET_PIPELINES_DIR is not true and pipelines directory exists and is not empty
  if [ "$RESET_PIPELINES_DIR" != true ] && [ -d "$PIPELINES_DIR" ] && [ "$(ls -A "$PIPELINES_DIR")" ]; then
    echo "Pipelines directory $PIPELINES_DIR already exists and is not empty. Skipping download."
  else
    # Split PIPELINES_URLS by ';' and iterate over each path
    IFS=';' read -ra ADDR <<< "$PIPELINES_URLS"
    for path in "${ADDR[@]}"; do
      download_pipelines "$path" "$PIPELINES_DIR"
    done
  fi

  find "$PIPELINES_DIR" -type f -name '*.py' | while read -r file; do
    install_frontmatter_requirements "$file"
  done
else
  echo "PIPELINES_URLS not specified. Skipping pipelines download and installation."
fi

echo "start.sh script completed successfully."
echo ""
exec uvicorn main:app --host "$HOST" --port "$PORT" --forwarded-allow-ips '*'