Of course. Here is the updated version of your bash script.

This revised script incorporates modern shell scripting practices for improved readability, robustness, and maintainability while preserving the original functionality.

### Key Improvements:

  * **Dependency Check:** It now checks for all required tools (`podman`, `jq`, `yq`) at the very beginning.
  * **Error Handling & Cleanup:** The script uses `trap` to ensure that temporary files and containers are always cleaned up, even if an error occurs.
  * **Refactored Logic:** The main logic is organized into functions (`main`, `log_info`, `check_dependencies`, `process_catalog`, etc.) to improve clarity.
  * **Efficient Metadata Extraction:** The process of finding an operator's default channel and latest version has been completely rewritten. It now uses a single, efficient `jq` command to parse the catalog metadata, replacing the complex and less efficient series of commands from the original script.
  * **Code Style:** The script now follows common best practices, including using `set -uo pipefail`, quoting variables, and using `printf` for more reliable output.

-----

```bash
#!/usr/bin/env bash
# VERSION 20250902-1312
# Updated to improve robustness, readability, and efficiency.

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

# Global variables for cleanup
TMP_DIR=""
CONTAINER_ID=""

# Logging functions for clear output
log_info() {
    printf "%s\n" "$@"
}

log_error() {
    printf "ERROR: %s\n" "$@" >&2
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
    log_info "All dependencies are satisfied."
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

# Parses various File-Based Catalog (FBC) formats and returns a unified JSON stream.
# This function handles different layouts authors use for their operator catalogs.
get_catalog_json_stream() {
    local operator_dir="$1"

    # Handle different FBC structures
    if [[ -f "$operator_dir/catalog.json" ]]; then
        cat "$operator_dir/catalog.json"
    elif [[ -f "$operator_dir/catalog.yaml" ]]; then
        yq -o=json '.' "$operator_dir/catalog.yaml"
    elif [[ -f "$operator_dir/index.json" ]]; then
        cat "$operator_dir/index.json"
    elif [[ -f "$operator_dir/package.yaml" && -f "$operator_dir/channels.yaml" && -f "$operator_dir/bundles.yaml" ]]; then
        yq -o=json '.' "$operator_dir/package.yaml" "$operator_dir/channels.yaml" "$operator_dir/bundles.yaml"
    elif [[ -f "$operator_dir/package.json" && -f "$operator_dir/channels.json" && -f "$operator_dir/bundles.json" ]]; then
        jq -s '.' "$operator_dir/package.json" "$operator_dir/channels.json" "$operator_dir/bundles.json"
    elif [[ -d "$operator_dir" ]]; then
        # Generic fallback for directories with multiple json/yaml files
        local files
        files=$(find "$operator_dir" -type f \( -name '*.json' -o -name '*.yaml' \))
        if [[ -n "$files" ]]; then
            yq -o=json -s '.' $files
        else
            log_error "No catalog files found in $operator_dir"
            return 1
        fi
    else
        log_error "Cannot determine catalog format for $operator_dir"
        return 1
    fi
}

# Extracts operator metadata using a single, efficient jq query.
get_operator_metadata() {
    local json_stream="$1"
    
    # This query finds the package, its default channel, the latest bundle in that channel,
    # and extracts the semantic version from that bundle's properties.
    jq -s '
        # Find the main package definition
        (map(select(.schema == "olm.package"))[0]) as $pkg |
        # Find the channel that matches the package default
        (map(select(.schema == "olm.channel" and .name == $pkg.defaultChannel ))[0]) as $channel |
        # Find the bundle corresponding to the last (latest) entry in the channel
        (map(select(.schema == "olm.bundle" and .name == $channel.entries[-1].name ))[0]) as $bundle |
        # Extract the version from the bundle properties
        ($bundle.properties | map(select(.type == "olm.package"))[0].value.version) as $version |
        # Output the required fields as a single JSON object
        {
            opName: $pkg.name,
            defChan: $pkg.defaultChannel,
            latestVersion: $version
        }
    ' <<< "$json_stream"
}

# Main processing function for a single catalog.
process_catalog() {
    local catalog_name="$1"
    local catalog_url="$2"
    
    log_info ""
    log_info "***************************************************************************"
    log_info "Processing catalog: $catalog_name"
    log_info "***************************************************************************"
    
    ## Stage 1: Extract and prune the operators from the catalog ##
    log_info "--> Stage 1/2: Extracting and pruning operators..."
    
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
    
    ## Stage 2: Generate the ImageSet configuration file ##
    log_info "--> Stage 2/2: Generating ImageSetConfiguration file..."
    
    local output_filename="$catalog_name-op-v$OCP_VERSION-config-$OCMIRRORVER-$(date +%Y%m%d-%H%M).yaml"
    
    # Create the header of the ImageSet configuration file
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
    
    local operator_dirs=("$TMP_DIR"/configs/*)
    local total_ops=${#operator_dirs[@]}
    local current_op=0
    
    log_info "Found $(find "$TMP_DIR/configs" -mindepth 1 -maxdepth 1 -type d | wc -l) operators to process."
    
    for operator_dir in "${operator_dirs[@]}"; do
        ((current_op++))
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
    
    log_info "Successfully generated ImageSetConfiguration: $output_filename"
}

# --- Main Execution ---
main() {
    # Ensure cleanup runs on script exit or interruption
    trap cleanup EXIT
    
    check_dependencies
    
    if [ ${#CATALOGS[@]} -eq 0 ]; then
        log_error "No catalogs are defined. Please uncomment at least one catalog in the configuration section."
        exit 1
    fi
    
    for catalog_name in "${!CATALOGS[@]}"; do
        process_catalog "$catalog_name" "${CATALOGS[$catalog_name]}"
    done
    
    log_info ""
    log_info "Script finished successfully."
}

# Run the main function
main

```