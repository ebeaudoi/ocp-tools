#!/usr/bin/env bash
# VERSION 20250903-1323
# Updated to improve robustness, readability, and efficiency by refactoring into functions.
# Added colorized output for better logging visibility.

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# Prevent errors in a pipeline from being masked.
set -o pipefail
# Enable extended globbing for the pruning step.
shopt -s extglob

########################################
########################################
# ** CONFIGURATION ** #

# 1 - oc-mirror version ('v1' or 'v2')
# v1 uses a 'metadata' path, v2 uses a cache.
OCMIRRORVER=v2

# 2 - Specify the OpenShift Container Platform version, e.g., 4.15, 4.16
OCP_VERSION=4.17

# 3 - Uncomment the catalogs containing the operators you need.
declare -A CATALOGS
CATALOGS["redhat"]="registry.redhat.io/redhat/redhat-operator-index:v$OCP_VERSION"
#CATALOGS["certified"]="registry.redhat.io/redhat/certified-operator-index:v$OCP_VERSION"
#CATALOGS["community"]="registry.redhat.io/redhat/community-operator-index:v$OCP_VERSION"
#CATALOGS["marketplace"]="registry.redhat.io/redhat/redhat-marketplace-index:v$OCP_VERSION"

# 4 - Specify the operators to keep, separated by a pipe '|'.
# This string is used as a pattern for filtering.
KEEP="openshift-cert-manager-operator|cincinnati-operator|advanced-cluster-management|amq7-interconnect-operator|amq-broker-rhel8|amq-online|amq-streams|cluster-logging|compliance-operator|datagrid|eap|elasticsearch-operator|gatekeeper-operator-product|jaeger-product|jws-operator|kiali-ossm|local-storage-operator|loki-operator|mcg-operator|multicluster-engine|nfd|ocs-operator|odf-csi-addons-operator|odf-operator|odr-cluster-operator|odr-hub-operator|openshift-gitops-operator|openshift-pipelines-operator-rh|opentelemetry-product|quay-operator|redhat-oadp-operator|rhacs-operator|rhbk-operator|rhods-operator|rhsso-operator|serverless-operator|servicemeshoperator"

########################################
########################################

# --- UTILITY FUNCTIONS ---

# Color definitions for logging output using ANSI-C quoting ($'...') to interpret escape sequences.
readonly C_RESET=$'\033[0m'
readonly C_RED=$'\033[0;31m'
readonly C_GREEN=$'\033[0;32m'
readonly C_YELLOW=$'\033[0;33m'
readonly C_CYAN=$'\033[0;36m'

# Global variables for cleanup
TMP_DIR=""
CONTAINER_ID=""

# Logging functions for clear, colorized output
log_info() {
    local message="$1"
    local color_code="${2:-}" # Second argument is the color code, defaults to empty
    
    if [[ -n "$color_code" ]]; then
        printf "%s%s%s\n" "$color_code" "$message" "$C_RESET"
    else
        printf "%s\n" "$message"
    fi
}

log_error() {
    # Errors are always printed in red to stderr
    printf "${C_RED}ERROR: %s${C_RESET}\n" "$@" >&2
}

# A pure Bash implementation of the 'basename' command to ensure portability.
basename() {
    local full_path="$1"
    printf "%s" "${full_path##*/}"
}

# Lists the operators specified in the KEEP variable with line numbers.
list_kept_operators() {
    log_info "--- Operators specified in the KEEP variable ---" "$C_CYAN"
    # Temporarily replace the pipe delimiter with a newline to list items,
    # then use nl to add line numbers for readability.
    echo "$KEEP" | tr '|' '\n' | nl
    log_info "--------------------------------------------" "$C_CYAN"
}

# Ensures all required command-line tools are available.
check_dependencies() {
    log_info "Checking for required tools..."
    local missing_deps=0
    for cmd in podman jq yq; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Command '$cmd' is not installed, but it is required."
            missing_deps=1
        fi
    done

    if [[ $missing_deps -eq 1 ]]; then
        log_error "Please install missing dependencies and try again."
        exit 1
    fi
    log_info "All dependencies are satisfied." "$C_GREEN"
}

# Cleanup function to be called on script exit.
cleanup() {
    if [[ -n "$CONTAINER_ID" ]]; then
        log_info "Attempting to stop and remove container ID: $CONTAINER_ID"
        podman rm --time 20 -f "$CONTAINER_ID" &>/dev/null || true
    fi
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
}

# --- CATALOG PROCESSING FUNCTIONS ---

# Sets up a temporary directory, pulls the catalog image, and prunes it.
setup_and_prune_catalog() {
    local catalog_url="$1"
    
    log_info "--> Stage 1/2: Extracting and pruning operators..." "$C_YELLOW"
    
    TMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: $TMP_DIR"
    
    log_info "Pulling the latest catalog image: $catalog_url"
    podman pull "$catalog_url"
    
    CONTAINER_ID=$(podman run -d "$catalog_url")
    log_info "Started temporary container with ID: $CONTAINER_ID"
    
    log_info "Copying catalog configs from container to $TMP_DIR/configs"
    podman cp "$CONTAINER_ID:/configs" "$TMP_DIR/configs"
    
    podman rm --time 20 -f "$CONTAINER_ID"
    CONTAINER_ID="" # Clear ID after removal
    log_info "Container removed."

    log_info "Pruning catalog to keep only specified operators..."
    (cd "$TMP_DIR/configs" && rm -rf !($KEEP))
}

# Creates the initial header for the ImageSetConfiguration YAML file.
create_imageset_header() {
    local output_filename="$1"
    local catalog_name="$2"
    local catalog_url="$3"

    log_info "--> Stage 2/2: Generating ImageSetConfiguration file..." "$C_YELLOW"
    {
        printf "kind: ImageSetConfiguration\n"
        if [[ "$OCMIRRORVER" == "v1" ]]; then
            printf "apiVersion: mirror.openshift.io/v1alpha2\n"
            printf "storageConfig:\n"
            printf "  local:\n"
            printf "    path: ./metadata/%s-catalog-v%s\n" "$catalog_name" "$OCP_VERSION"
        else # v2
            printf "apiVersion: mirror.openshift.io/v2alpha1\n"
        fi
        printf "mirror:\n"
        printf "  operators:\n"
        printf "  - catalog: %s\n" "$catalog_url"
        printf "    targetCatalog: %s-catalog-index\n" "$catalog_name"
        printf "    packages:\n"
    } > "$output_filename"
}

# Parses various File-Based Catalog (FBC) formats and returns a unified JSON stream.
# This version is more efficient by finding all files first and then processing them in a single command.
get_catalog_json_stream() {
    local operator_dir="$1"

    # Find all relevant files once. Use an array to handle spaces in filenames.
    local files=()
    while IFS= read -r -d $'\0'; do
        files+=("$REPLY")
    done < <(find "$operator_dir" -type f \( -name '*.json' -o -name '*.yaml' \) -print0)

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No catalog files (json/yaml) found in $operator_dir"
        return 1
    fi

    # Check if any YAML files are present in the list.
    local has_yaml=false
    for file in "${files[@]}"; do
        if [[ "$file" == *.yaml ]]; then
            has_yaml=true
            break
        fi
    done

    # If YAML files are present, yq is required and can handle both formats.
    # Otherwise, jq is sufficient and more robust for JSON streams.
    if [[ "$has_yaml" == true ]]; then
        # Process all files with yq. It reads multiple files and outputs a stream of JSON objects.
        yq -o=json '.' "${files[@]}" 2>/dev/null
    else
        # Process all JSON files with jq.
        jq '.' "${files[@]}" 2>/dev/null
    fi
}

# Extracts key operator metadata from a JSON stream.
get_operator_metadata() {
    local json_stream="$1"
    jq -s '
        (map(select(.schema == "olm.package"))[0]) as $pkg |
        (map(select(.schema == "olm.channel" and .name == $pkg.defaultChannel ))[0]) as $channel |
        (map(select(.schema == "olm.bundle" and .name == $channel.entries[-1].name ))[0]) as $bundle |
        ($bundle.properties | map(select(.type == "olm.package"))[0].value.version) as $version |
        {
            opName: $pkg.name,
            defChan: $pkg.defaultChannel,
            latestVersion: $version
        }
    ' <<< "$json_stream"
}

# Compares the KEEP list against the actual directories found after pruning and logs any missing operators.
verify_operators_found() {
    # Create an associative array for efficient lookup of found operator basenames.
    declare -A found_operators
    for dir_path in "$@"; do
        if [[ -d "$dir_path" ]]; then
            found_operators["$(basename "$dir_path")"]=1
        fi
    done

    log_info "Verifying that all specified operators were found in the catalog..."
    # Iterate over each operator in the KEEP variable.
    echo "$KEEP" | tr '|' '\n' | while IFS= read -r operator; do
        [[ -z "$operator" ]] && continue
        
        # Check if the operator from the KEEP list exists in our associative array of found directories.
        if [[ ! -v "found_operators[$operator]" ]]; then
            log_error "WARNING: Operator '$operator' from the KEEP list was not found in the catalog and will be skipped."
        fi
    done
    log_info "Verification complete."
}

# Iterates through operator directories and processes them.
process_operators() {
    local output_filename="$1"

    local operator_dirs=("$TMP_DIR"/configs/*)
    
    # Verify that the operators we expect to find are actually present.
    verify_operators_found "${operator_dirs[@]}"
    
    local total_ops=${#operator_dirs[@]}
    local current_op=0
    
    log_info "Found $(find "$TMP_DIR/configs" -mindepth 1 -maxdepth 1 -type d | wc -l) operators to process."
    
    for operator_dir in "${operator_dirs[@]}"; do
        let current_op+=1
        local operator_basename
        operator_basename=$(basename "$operator_dir")
        
        log_info "--- Processing ($current_op/$total_ops): $operator_basename ---"
        
        local json_stream
        json_stream=$(get_catalog_json_stream "$operator_dir")
        
        if [[ -z "$json_stream" ]]; then
            log_error "Could not generate a JSON stream for $operator_basename. Skipping."
            continue
        fi
        
        local metadata
        metadata=$(get_operator_metadata "$json_stream")
        
        if [[ -z "$metadata" || "$metadata" == "null" ]]; then
            log_error "Failed to extract metadata for $operator_basename. Skipping."
            continue
        fi

        local op_name def_chan latest_version
        op_name=$(jq -r '.opName' <<< "$metadata")
        def_chan=$(jq -r '.defChan' <<< "$metadata")
        latest_version=$(jq -r '.latestVersion' <<< "$metadata")
        
        log_info "    Adding: name='$op_name', channel='$def_chan', minVersion='$latest_version'"
        
        # Append the operator details to the output file
        {
            printf "    - name: %s\n" "$op_name"
            printf "      channels:\n"
            printf "      - name: %s\n" "$def_chan"
            printf "        minVersion: %s\n" "$latest_version"
        } >> "$output_filename"
    done
    
    log_info "Successfully generated ImageSetConfiguration: $output_filename" "$C_GREEN"
}


# --- MAIN EXECUTION ---
main() {
    trap cleanup EXIT
    
    check_dependencies
    list_kept_operators
    
    if [ ${#CATALOGS[@]} -eq 0 ]; then
        log_error "No catalogs are defined. Please uncomment at least one catalog in the configuration section."
        exit 1
    fi
    
    for catalog_name in "${!CATALOGS[@]}"; do
        local catalog_url="${CATALOGS[$catalog_name]}"
        log_info ""
        log_info "***************************************************************************" "$C_YELLOW"
        log_info "Processing catalog: $catalog_name" "$C_YELLOW"
        log_info "***************************************************************************" "$C_YELLOW"
        
        setup_and_prune_catalog "$catalog_url"
        
        local output_filename="$catalog_name-op-v$OCP_VERSION-config-$OCMIRRORVER-$(date +%Y%m%d-%H%M).yaml"
        create_imageset_header "$output_filename" "$catalog_name" "$catalog_url"
        
        process_operators "$output_filename"
    done
    
    log_info ""
    log_info "Script finished successfully." "$C_GREEN"
}

# Run the main function
main

