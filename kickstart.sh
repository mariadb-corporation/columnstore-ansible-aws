#!/usr/bin/env bash
# This script is used to fill Terraform variables and generally help set up the Columnstore cluster
set -e # Exit on errors
set -o pipefail

# Helpful error tracer
trap 'echo "ERROR: Command failed on line $LINENO: $BASH_COMMAND" >&2' ERR

# Enable shell tracing when DEBUG_KICKSTART=1 is set
if [[ "${DEBUG_KICKSTART:-0}" == "1" ]]; then
  set -x
fi

AWS_REGION="us-west-2"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (reset)

# Here we will store info about changes made during this script run
CHANGELOG=()

note() {
    echo -e "${YELLOW}NOTE:${NC} $*"
}

warn() {
    echo -e "${RED}WARNING:${NC} $*"
}

in_green() {
    echo -e "${GREEN}$*${NC}"
}

log_change() {
    local msg="$1"
    CHANGELOG+=("$msg")
}

# Safely mask sensitive values for display
mask_value() {
    local v="$1"
    local len=${#v}
    if (( len == 0 )); then
        echo "(empty)"
    elif (( len <= 6 )); then
        echo "${v:0:1}***${v: -1}"
    else
        echo "${v:0:3}***${v: -3}"
    fi
}

get_distro_type() {
    if command -v apt-get &> /dev/null; then
        echo "debian"
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        echo "redhat"
    else
        echo "unknown"
        return 1
    fi
}

install_package() {
    # TODO extract package name from distro files in inventory
    local package_name="$1"
    local distro_type=$(get_distro_type)

    echo "Installing $package_name..."

    if [ "$distro_type" == "debian" ]; then
        sudo apt-get update -y && sudo apt-get install -y "$package_name"
    elif [ "$distro_type" == "redhat" ]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y "$package_name"
        else
            sudo yum install -y "$package_name"
        fi
    else
        echo "Unsupported distribution. Please install $package_name manually."
        return 1
    fi

    echo "$package_name installed successfully."
}

install_aws_cli() {
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

    if ! command -v unzip &> /dev/null; then
        install_package "unzip"
    fi

    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
    echo "AWS CLI installed successfully."
}

get_current_var_value() {
    local var_name="$1"
    local default_value="${2:-}"

    if [ -f terraform.tfvars ]; then
        local line
        line=$(grep -E "^$var_name[[:space:]]*=" terraform.tfvars | head -n1)
        if [ -n "$line" ]; then
            # Extract RHS after first '=' and trim surrounding spaces and optional quotes, preserving inner spaces
            local value
            value=$(echo "$line" | sed -E 's/^[^=]+=//; s/^[[:space:]]*\"?//; s/\"?[[:space:]]*$//')
            if [ -n "$value" ]; then
                echo "$value"
            else
                echo "$default_value"
            fi
        else
            echo "$default_value"
        fi
    else
        echo "$default_value"
    fi
}

ask_boolean() {
    local var_name="$1"
    local prompt="$2"
    local current_value="$3"

    local yn_prompt
    if [[ "$current_value" == "true" ]]; then
        yn_prompt="Y/n"
    elif [[ "$current_value" == "false" ]]; then
        yn_prompt="y/N"
    else
        yn_prompt="y/n"
    fi

    local answer
    read -p "$prompt [$yn_prompt]: " answer

    if [[ -z "$answer" ]]; then
        answer="$current_value"
    fi

    case "$answer" in
        [Yy]*|true) echo "true";;
        [Nn]*|false) echo "false";;
        *) echo "Invalid input. Assuming false."; echo "false";;
    esac
}

propose_change_value() {
    local var_name="$1"
    local must_mask_value="${2:-false}"
    local description="${3:-}"
    local current_value=$(get_current_var_value "$var_name")
    local cur_value_to_show="$current_value"
    if [ "$must_mask_value" = "true" ] && [ -n "$current_value" ]; then
        cur_value_to_show="${current_value:0:3}***${current_value: -3}"
    fi

    local prompt=""
    if [ -n "$description" ]; then
        prompt="$description "
    else
        prompt="Enter value for $var_name "
    fi
    prompt+="['$cur_value_to_show']: "

    read -p "$prompt" new_value

    if [ -z "$new_value" ]; then
        new_value="$current_value"
    fi

    set_var_value "$var_name" "$new_value"
    echo ""
}

set_var_value() {
    local var_name="$1"
    local var_value="$2"
    local must_mask_value="${3:-false}"

    # Escape special characters for safe sed replacement
    local escaped_value
    escaped_value=$(printf '%s' "$var_value" | sed -e 's/[\/&|]/\\&/g')

    local tmpfile
    tmpfile=$(mktemp)

    masked_value=$var_value
    if [ "$must_mask_value" = "true" ]; then
        masked_value="${var_value:0:3}***${var_value: -3}"
    fi

    if grep -qE "^$var_name[[:space:]]*=" terraform.tfvars; then
        local current_value=$(get_current_var_value "$var_name")

        # Replace the line with the updated value
        sed "s|^$var_name[[:space:]]*=.*|$var_name = \"$escaped_value\"|" terraform.tfvars > "$tmpfile"

        # Only log if value changed
        if [ "$current_value" != "$var_value" ]; then
            log_change "Updated $var_name in terraform.tfvars to '$masked_value'"
        fi
    else
        # Append new variable at the end of the file
        cat terraform.tfvars > "$tmpfile"
        echo "$var_name = \"$var_value\"" >> "$tmpfile"
        log_change "Added $var_name to terraform.tfvars with value '$masked_value'"
    fi

    mv "$tmpfile" terraform.tfvars
}

choose_distro() {
    # distro to AMI mapping
    declare -A distro_ami_map
    distro_ami_map=(
        ["Ubuntu 24.04"]="ami-05f991c49d264708f"
        ["Ubuntu 22.04"]="ami-0ec1bf4a8f92e7bd1"
        ["Ubuntu 20.04"]="ami-01f99b4d609a9f41e"
        ["Rocky 9"]="ami-0adebe3adcec1fa34"
        ["Rocky 8"]="ami-0f74cc83310468775"
        ["Debian 12"]="ami-03420506796dd6873"
    )

    # Create reverse mapping (AMI to distro)
    declare -A ami_to_distro
    for distro in "${!distro_ami_map[@]}"; do
        ami_to_distro["${distro_ami_map[$distro]}"]="$distro"
    done

    # Check if aws_ami is already set
    local current_ami=$(get_current_var_value "aws_ami")
    local matched_distro="Unknown"

    if [ -n "$current_ami" ]; then
        # Try to match the current AMI to a known distribution
        if [[ -n "${ami_to_distro[$current_ami]}" ]]; then
            matched_distro="${ami_to_distro[$current_ami]}"
            echo "Current AMI matches distribution: $matched_distro"
        else
            echo "Current AMI ($current_ami) doesn't match any known distribution"
            matched_distro="Custom AMI"
        fi

        local change_ami=$(ask_boolean "change_ami" "AWS AMI is already set to '$current_ami' ($matched_distro). Do you want to change it?" "false")
        if [[ "$change_ami" == "false" ]]; then
            echo "Keeping current AMI: $current_ami"
            echo ""
            return
        fi
    fi

    # Add the Custom AMI option to the mapping
    distro_ami_map["Custom AMI"]="custom"

    # Using associative array to store distro:AMI pairs
    echo "Choose distribution for AWS instances (AMIs are region-dependent, these are from $AWS_REGION region):"

    # Convert associative array keys to indexed array for numbered selection
    distro_options=("${!distro_ami_map[@]}")

    # Sort the options alphabetically but keep "Custom AMI" at the end
    sorted_options=()
    for option in "${distro_options[@]}"; do
        if [ "$option" != "Custom AMI" ]; then
            sorted_options+=("$option")
        fi
    done
    # Sort the standard options
    IFS=$'\n' sorted_options=($(sort <<<"${sorted_options[*]}"))
    unset IFS
    # Add Custom AMI at the end
    sorted_options+=("Custom AMI")

    # Display options
    for i in "${!sorted_options[@]}"; do
        echo "[$i] ${sorted_options[$i]}"
    done

    while true; do
        read -p "Select distribution [0-$((${#sorted_options[@]}-1))]: " distro_choice

        # Validate input is a number and within range
        if [[ "$distro_choice" =~ ^[0-9]+$ ]] && [ "$distro_choice" -ge 0 ] && [ "$distro_choice" -lt "${#sorted_options[@]}" ]; then
            break
        else
            echo "Invalid choice. Please select a number between 0 and $((${#sorted_options[@]}-1))"
        fi
    done

    selected_distro="${sorted_options[$distro_choice]}"
    selected_ami="${distro_ami_map[$selected_distro]}"

    if [ "$selected_ami" == "custom" ]; then
        read -p "Enter custom AMI ID: " custom_ami
        selected_ami="$custom_ami"
    fi

    echo "Setting AWS AMI to: $selected_ami ($selected_distro)"
    set_var_value "aws_ami" "$selected_ami"
    echo ""
}

get_aws_imds_token() {
    curl -s --fail --connect-timeout 3 -X PUT "http://169.254.169.254/latest/api/token" \
         -H "X-aws-ec2-metadata-token-ttl-seconds: 60"
}

detect_cloud_environment() {
  # Try AWS EC2 IMDSv2 first
  local token instance_id

  token=$(get_aws_imds_token)
  if [[ -n "$token" ]]; then
    instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/instance-id)

    if [[ "$instance_id" =~ ^i-[a-z0-9]+$ ]]; then
      echo "aws"
      return 0
    fi
  fi

  # Check GCE only if AWS check failed
  gce_id=$(curl -s -H "Metadata-Flavor: Google" \
    --connect-timeout 1 \
    http://169.254.169.254/computeMetadata/v1/instance/id)

  if [[ -n "$gce_id" ]]; then
    echo "gce"
    return 0
  fi

  echo "unknown"
  return 1
}

show_aws_identity() {
    echo "AWS Identity:"
    aws sts get-caller-identity \
        --query '{Account:Account, User:Arn}' \
        --output table
}

is_sso_profile() {
    local profile_name="$1"
    # If profile has sso parameters in config, it is SSO
    local sso_start_url sso_session
    sso_start_url=$(aws configure get sso_start_url --profile "$profile_name" 2>/dev/null || true)
    sso_session=$(aws configure get sso_session --profile "$profile_name" 2>/dev/null || true)
    if [[ -n "$sso_start_url" || -n "$sso_session" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

ensure_profile_credentials() {
    local profile_name="$1"
    local is_sso
    is_sso=$(is_sso_profile "$profile_name")

    # Always set the aws_profile variable
    set_var_value aws_profile "$profile_name"

    if [[ "$is_sso" == "true" ]]; then
        echo "Detected SSO profile: $profile_name"
        # Try to export credentials
        local creds_json expiration now_epoch exp_epoch
        # Use 'process' format which outputs JSON suitable for parsing
        creds_json=$(aws configure export-credentials --profile "$profile_name" --format process 2>/dev/null || true)

        if [[ -n "$creds_json" ]]; then
            # 'process' format returns top-level fields; also support nested Credentials and various casings
            expiration=$(echo "$creds_json" | jq -r '(.Credentials.Expiration // .Expiration // .expiration // empty)' 2>/dev/null || true)
        fi

        # Determine if we need to login
        local need_login="false"
        if [[ -z "$creds_json" ]]; then
            # If export-credentials is empty, check whether the profile already works; if yes, don't force login
            if AWS_PROFILE="$profile_name" aws sts get-caller-identity >/dev/null 2>&1; then
                need_login="false"
            else
                need_login="true"
            fi
        else
            if [[ -z "$expiration" || "$expiration" == "null" ]]; then
                # If we cannot parse expiration, check if the profile is currently usable
                if AWS_PROFILE="$profile_name" aws sts get-caller-identity >/dev/null 2>&1; then
                    need_login="false"
                else
                    need_login="true"
                fi
            else
                now_epoch=$(date -u +%s)
                exp_epoch=$(date -u -d "$expiration" +%s 2>/dev/null || echo 0)
                minutes_left=$(( (exp_epoch - now_epoch) / 60 ))
                if (( minutes_left < 20 )); then
                    echo "AWS credentials are expiring in $minutes_left minutes, re-authenticating..."
                    need_login="true"
                else
                    echo "AWS credentials are valid for $minutes_left minutes, no need to re-authenticate."
                fi
            fi
        fi

        if [[ "$need_login" == "true" ]]; then
            echo "Logging in to AWS SSO for profile '$profile_name' (device code flow)..."
            aws sso login --profile "$profile_name" --use-device-code
            # Re-export after login (process format emits JSON)
            creds_json=$(aws configure export-credentials --profile "$profile_name" --format process)
        fi

        # Parse and store credentials
        local access_key secret_key session_token
        access_key=$(echo "$creds_json" | jq -r '.Credentials.AccessKeyId // .AccessKeyId')
        secret_key=$(echo "$creds_json" | jq -r '.Credentials.SecretAccessKey // .SecretAccessKey')
        session_token=$(echo "$creds_json" | jq -r '.Credentials.SessionToken // .SessionToken')

        if [[ -z "$access_key" || -z "$secret_key" || -z "$session_token" ]]; then
            echo "Failed to obtain SSO temporary credentials for profile '$profile_name'"
            return 1
        fi

        set_var_value aws_access_key "$access_key"
        set_var_value aws_secret_key "$secret_key"
        set_var_value aws_session_token "$session_token"

        echo "SSO credentials exported and saved to terraform.tfvars."
    else
        # Static or non-SSO profile
        local key secret token
        key=$(aws configure get aws_access_key_id --profile "$profile_name")
        secret=$(aws configure get aws_secret_access_key --profile "$profile_name")
        token=$(aws configure get aws_session_token --profile "$profile_name")

        if [[ -z "$key" || -z "$secret" ]]; then
            echo "Failed to extract credentials from non-SSO profile '$profile_name'"
            return 1
        fi
        set_var_value aws_access_key "$key"
        set_var_value aws_secret_key "$secret"
        set_var_value aws_session_token "$token"
        echo "Static credentials saved to terraform.tfvars."
    fi

    # Show identity with the selected profile
    AWS_PROFILE="$profile_name" show_aws_identity

    # Make the selected profile active for the remainder of this script run
    export AWS_PROFILE="$profile_name"
    CURRENT_SELECTED_AWS_PROFILE="$profile_name"
    return 0
}

# Let user select or create a profile (supports SSO)
select_or_create_aws_profile() {
    # Ensure AWS CLI v2 is available (already checked earlier)
    echo "Available AWS profiles:"
    local profiles=()
    while IFS= read -r p; do
        profiles+=("$p")
    done < <(aws configure list-profiles 2>/dev/null)

    if [ ${#profiles[@]} -eq 0 ]; then
        echo "No AWS profiles found. You can create a standard or SSO profile (aws configure sso)."
    fi

    # Display with SSO markers
    local i=1
    for p in "${profiles[@]}"; do
        local mark=""
        if [[ $(is_sso_profile "$p") == "true" ]]; then
            mark=" [SSO]"
        fi
        echo "  [$i] $p$mark"
        ((i++))
    done
    echo "  [N] Create a new standard profile"
    echo

    # If terraform.tfvars already specifies aws_profile and it exists locally, offer to switch to it
    local tfvars_profile
    tfvars_profile=$(get_current_var_value "aws_profile")
    if [[ -n "$tfvars_profile" ]]; then
        local exists=false
        for p in "${profiles[@]}"; do
            if [[ "$p" == "$tfvars_profile" ]]; then
                exists=true
                break
            fi
        done
        if $exists; then
            if [[ "$(ask_boolean switch_to_tfvars_profile \"Detected aws_profile=\\\"$tfvars_profile\\\" in terraform.tfvars. Switch to it now?\" \"true\")" == "true" ]]; then
                echo "Using profile: $tfvars_profile"
                ensure_profile_credentials "$tfvars_profile"
                return 0
            fi
        fi
    fi

    read -p "Choose profile number or 'N': " choice
    local profile_name

    if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#profiles[@]} ]]; then
        profile_name="${profiles[$((choice-1))]}"
        echo "Using profile: $profile_name"
    elif [[ "$choice" =~ ^[Nn]$ ]]; then
        read -p "Enter name for new profile: " profile_name
        aws configure --profile "$profile_name"
        log_change "Created new AWS profile '$profile_name'"
    else
        echo "Invalid choice."
        return 1
    fi

    # After selection/creation, ensure we have usable credentials and save them
    ensure_profile_credentials "$profile_name"
    return 0
}

sync_terraform_vars_with_aws_credentials() {
    local actual_key actual_secret actual_profile effective_profile is_sso
    local saved_key saved_secret saved_profile
    local need_update=false

    # Prefer the profile selected earlier in this script; fall back to environment; then default
    effective_profile="${CURRENT_SELECTED_AWS_PROFILE:-${AWS_PROFILE:-default}}"
    is_sso=$(is_sso_profile "$effective_profile")
    # For SSO profiles, do NOT derive keys from 'aws configure get' (it will be empty). Keep existing exported keys.
    if [[ "$is_sso" == "true" ]]; then
        actual_key=$(get_current_var_value "aws_access_key")
        actual_secret=$(get_current_var_value "aws_secret_key")
    else
        # Make aws configure get robust even if values are unset
        actual_key=$(aws configure get aws_access_key_id --profile "$effective_profile" 2>/dev/null || true)
        actual_secret=$(aws configure get aws_secret_access_key --profile "$effective_profile" 2>/dev/null || true)
    fi
    actual_profile="$effective_profile"

    saved_key=$(get_current_var_value "aws_access_key")
    saved_secret=$(get_current_var_value "aws_secret_key")
    saved_profile=$(get_current_var_value "aws_profile")

    if [[ "$actual_key" != "$saved_key" ]]; then
        echo "terraform.tfvars aws_access_key: $(mask_value "$saved_key")"
        echo "Current profile aws_access_key: $(mask_value "$actual_key")"
        need_update=true
    fi

    if [[ "$actual_secret" != "$saved_secret" ]]; then
        echo "terraform.tfvars aws_secret_key differs from current profile"
        need_update=true
    fi

    if [[ "$actual_profile" != "$saved_profile" ]]; then
        echo "terraform.tfvars aws_profile: ${saved_profile:-'(empty)'}"
        echo "Current profile: $actual_profile"
        need_update=true
    fi

    if $need_update; then
        local sync=$(ask_boolean "sync_aws_credentials" "Do you want to update terraform.tfvars with the current AWS CLI credentials and profile?" "true")
        if [[ "$sync" == "true" ]]; then
            # Update profile always; only update keys for non-SSO (SSO keys already exported earlier)
            if [[ "$is_sso" == "true" ]]; then
                set_var_value aws_profile "$actual_profile"
            else
                set_var_value aws_access_key "$actual_key"
                set_var_value aws_secret_key "$actual_secret"
                set_var_value aws_profile "$actual_profile"
            fi
            echo "terraform.tfvars updated"
        else
            echo "terraform.tfvars not modified"
        fi
        echo ""
    fi
    return 0
}

choose_aws_key_pair() {
    echo "AWS EC2 Key Pair Selection"
    echo "[1] Use existing AWS key pair (with local private key)"
    echo "[2] Create new key pair and save private key locally"
    echo ""

    local choice
    read -p "Choose an option [1/2]: " choice

    if [[ "$choice" == "1" ]]; then
        echo "Fetching AWS key pairs..."
        local aws_keys_raw
        aws_keys_raw=$(aws ec2 describe-key-pairs --query "KeyPairs[*].KeyName" --output text 2>/dev/null)

        if [ $? -ne 0 ]; then
            echo "Failed to list AWS key pairs. Check credentials and permissions."
            return 1
        fi

        IFS=$'\t' read -ra aws_keys <<< "$aws_keys_raw"

        echo "Searching for local .pem files..."
        local local_pems=()
        while IFS= read -r pem; do
            local_pems+=("$pem")
        done < <(find ~/.ssh . -maxdepth 1 -type f -name "*.pem" 2>/dev/null)

        declare -A pem_paths
        for path in "${local_pems[@]}"; do
            filename=$(basename "$path")
            key_name="${filename%.pem}"
            pem_paths["$key_name"]="$path"
        done

        local matched_keys=()
        for key in "${aws_keys[@]}"; do
            if [[ -n "${pem_paths[$key]}" ]]; then
                matched_keys+=("$key")
            fi
        done

        if [ ${#matched_keys[@]} -eq 0 ]; then
            echo "No AWS key pairs match your local .pem files."
            return 1
        fi

        echo ""
        echo "Available key pairs with local private key:"
        for i in "${!matched_keys[@]}"; do
            echo "  [$i] ${matched_keys[$i]} (file: ${pem_paths[${matched_keys[$i]}]})"
        done

        echo ""
        read -p "Choose key number: " key_choice
        if [[ "$key_choice" =~ ^[0-9]+$ && "$key_choice" -ge 0 && "$key_choice" -lt "${#matched_keys[@]}" ]]; then
            local selected_key="${matched_keys[$key_choice]}"
            local selected_pem="${pem_paths[$selected_key]}"

            echo "Selected key pair: $selected_key"
            echo "Using private key file: $selected_pem"

            # Check if the PEM file has correct permissions (should be 400)
            pem_perms=$(stat -c "%a" "$selected_pem" 2>/dev/null)
            if [ "$pem_perms" != "400" ]; then
                echo "PEM file '$selected_pem' has permissions $pem_perms, correcting to 400..."
                chmod 400 "$selected_pem"
                if [ $? -eq 0 ]; then
                    echo "Permissions for '$selected_pem' set to 400."
                else
                    echo "Failed to set permissions for '$selected_pem'."
                fi
            fi

            set_var_value key_pair_name "$selected_key"
            set_var_value ssh_key_file "$selected_pem"
            set_var_value create_key_pair "false"
        else
            echo "Invalid choice."
            return 1
        fi

    elif [[ "$choice" == "2" ]]; then
        read -p "Enter name for new key pair: " selected_key
        local pem_file="./${selected_key}.pem"

        set_var_value create_key_pair "true"
        set_var_value key_pair_name "$selected_key"
        set_var_value ssh_key_file "$pem_file"
        echo "New key pair will be created: $selected_key"
        echo "Private key will be saved to: $pem_file"
    else
        echo "Invalid option."
        return 1
    fi
}

check_or_choose_aws_key_pair() {
    local current_key_pair=$(get_current_var_value "key_pair_name")
    local current_key_file=$(get_current_var_value "ssh_key_file")
    local current_create_key_pair=$(get_current_var_value "create_key_pair")

    if [ -n "$current_key_pair" ] && [ -n "$current_key_file" ] && [ "$current_create_key_pair" != "null" ]; then
        echo "Current AWS key pair is set:"
        echo "  key_pair_name = $current_key_pair"
        echo "  ssh_key_file  = $current_key_file"
        echo "  create_key_pair = $current_create_key_pair"

        if [[ "$PROMPT_ONLY_UNSET" == "true" ]]; then
            return
        fi

        change_keys=$(ask_boolean "change_aws_key_pair" "Do you want to change it?" "false")
        if [[ "$change_keys" == "false" ]]; then
            echo "Keeping current key pair."
            echo ""
            return
        fi
    fi

    choose_aws_key_pair
}

choose_or_create_vpc_and_sg() {
    echo ""
    echo "Checking existing VPCs..."
    local vpcs=()
    while IFS= read -r vpc; do
        vpcs+=("$vpc")
    done < <(aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`]|[0].Value]' --output text)

    if [ "${#vpcs[@]}" -eq 0 ]; then
        echo "No VPCs found. You will need to create one."
    else
        echo "Available VPCs:"
        for i in "${!vpcs[@]}"; do
            local id name
            id=$(awk '{print $1}' <<< "${vpcs[$i]}")
            name=$(awk '{print $2}' <<< "${vpcs[$i]}")
            echo "  [$i] $id ($name)"
        done
        echo "  [N] Create new VPC"
    fi

    read -p "Choose VPC number or 'N': " vpc_choice
    local vpc_id

    if [[ "$vpc_choice" =~ ^[0-9]+$ ]] && [ "$vpc_choice" -ge 0 ] && [ "$vpc_choice" -lt "${#vpcs[@]}" ]; then
        vpc_id=$(awk '{print $1}' <<< "${vpcs[$vpc_choice]}")
    else
        echo "Creating new VPC..."
        vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
        aws ec2 create-tags --resources "$vpc_id" --tags Key=Name,Value="mcs-vpc"
        echo "Created VPC: $vpc_id"
        log_change "Created new VPC with ID '$vpc_id'"
    fi

    set_var_value "aws_vpc" "$vpc_id"
    echo ""

    # Get or create subnet
    echo "Checking existing subnets in VPC $vpc_id..."
    local subnets=()
    while IFS= read -r subnet; do
        subnets+=("$subnet")
    done < <(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output text)

    if [ "${#subnets[@]}" -eq 0 ]; then
        echo "No subnets found. Creating a default one..."
        local az
        az=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
        subnet_id=$(aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block 10.0.1.0/24 --availability-zone "$az" --query 'Subnet.SubnetId' --output text)
        echo "Created subnet: $subnet_id in $az"
        log_change "Created new subnet with ID '$subnet_id' in VPC '$vpc_id'"
    else
        echo "Available subnets:"
        for i in "${!subnets[@]}"; do
            echo "  [$i] ${subnets[$i]}"
        done
        read -p "Choose subnet number: " subnet_choice
        subnet_id=$(awk '{print $1}' <<< "${subnets[$subnet_choice]}")
    fi

    set_var_value "aws_subnet" "$subnet_id"

    echo ""
}

check_or_choose_vpc_and_sg() {
    local current_vpc=$(get_current_var_value "aws_vpc")
    local current_subnet=$(get_current_var_value "aws_subnet")
    local current_sg=$(get_current_var_value "security_group_name")
    local use_shared_efs=$(get_current_var_value "create_shared_efs")

    # If creating shared EFS, use this host's VPC and subnet
    if [[ "$use_shared_efs" == "true" && "$shared_efs_include_dev_host" == "true" ]]; then
        echo "Shared EFS requires using this host's VPC and subnet for connectivity."
        local vpc_info=$(get_this_host_vpc_info)

        if [ $? -eq 0 ]; then
            local host_vpc_id=$(echo "$vpc_info" | awk '{print $1}')
            local host_subnet_id=$(echo "$vpc_info" | awk '{print $2}')

            echo "Using this host's network configuration:"
            echo "  VPC:    $host_vpc_id"
            echo "  Subnet: $host_subnet_id"

            set_var_value "aws_vpc" "$host_vpc_id"
            set_var_value "aws_subnet" "$host_subnet_id"

            echo "Network configuration set for shared EFS."
            echo ""
            return
        else
            echo "Failed to get VPC info for this host. Falling back to manual selection."
        fi
    fi

    if [[ -n "$current_vpc" && -n "$current_subnet" && -n "$current_sg" ]]; then
        echo "Current VPC/Subnet/SG values:"
        echo "  aws_vpc              = $current_vpc"
        echo "  aws_subnet           = $current_subnet"
        local deployment_prefix=$(get_current_var_value "deployment_prefix")
        if [ -n "$deployment_prefix" ]; then
            echo "  security_group_name  = ${deployment_prefix}_${current_sg}"
        else
            echo "  security_group_name  = $current_sg"
        fi

        local change_vpc=$(ask_boolean "change_vpc" "Do you want to change these values?" "false")
        if [[ "$change_vpc" != "true" ]]; then
            echo "Keeping existing network configuration."
            echo ""
            return
        fi
    fi

    choose_or_create_vpc_and_sg
    echo ""
}

get_this_host_availability_zone() {
    local token=$(get_aws_imds_token)
    zone=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
        http://169.254.169.254/latest/meta-data/placement/availability-zone)

    echo $zone;
}

get_this_host_region() {
    local az=$(get_this_host_availability_zone)
    if [ -z "$az" ]; then
        return 1
    fi
    # Remove the last character from the AZ to get the region
    echo ${az::-1}
}

get_this_host_vpc_info() {
    local token=$(get_aws_imds_token)
    local instance_id
    local vpc_id
    local subnet_id

    instance_id=$(get_aws_instance_id)

    if [ -z "$instance_id" ]; then
        echo "Failed to get instance ID" >&2
        return 1
    fi

    # Get VPC and subnet info for this instance
    local instance_info
    instance_info=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{VpcId:VpcId,SubnetId:SubnetId}' \
        --output json)

    vpc_id=$(echo "$instance_info" | jq -r '.VpcId')
    subnet_id=$(echo "$instance_info" | jq -r '.SubnetId')

    echo "$vpc_id $subnet_id"
}

is_subnet_public() {
    local subnet_id="$1"

    # Get the route table(s) associated with the subnet
    local rtb_ids
    rtb_ids=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$subnet_id" \
        --query "RouteTables[*].RouteTableId" --output text)

    # If no explicit association, use the main route table for the VPC
    if [ -z "$rtb_ids" ]; then
        local vpc_id
        vpc_id=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].VpcId' --output text)
        rtb_ids=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=true" \
            --query "RouteTables[*].RouteTableId" --output text)
    fi

    # Check each route table for a 0.0.0.0/0 route to an IGW
    for rtb_id in $rtb_ids; do
        local igw_route
        igw_route=$(aws ec2 describe-route-tables --route-table-ids "$rtb_id" \
            --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0' && contains(GatewayId, 'igw-')]" \
            --output text)
        if [ -n "$igw_route" ]; then
            # Optionally, check auto-assign public IP
            local public_ip
            public_ip=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].MapPublicIpOnLaunch' --output text)
            if [ "$public_ip" == "True" ]; then
                echo "public"
            else
                echo "public (but auto-assign public IP is disabled)"
            fi
            return 0
        fi
    done

    echo "private"
    return 1
}

make_subnet_public() {
    local subnet_id="$1"

    # Get VPC ID for the subnet
    local vpc_id
    vpc_id=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].VpcId' --output text)
    if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
        echo "Could not determine VPC for subnet $subnet_id"
        return 1
    fi

    # Ensure VPC has an Internet Gateway
    local igw_id
    igw_id=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ -z "$igw_id" ] || [ "$igw_id" == "None" ]; then
        igw_id=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
        aws ec2 attach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id"
        echo "Created and attached Internet Gateway: $igw_id"
    else
        echo "VPC $vpc_id already has Internet Gateway: $igw_id"
    fi

    # Find or create a route table with a default route to the IGW
    local rtb_id
    rtb_id=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" \
        --query "RouteTables[?Routes[?DestinationCidrBlock=='0.0.0.0/0' && GatewayId=='$igw_id']].RouteTableId" --output text)
    if [ -z "$rtb_id" ]; then
        rtb_id=$(aws ec2 create-route-table --vpc-id "$vpc_id" --query 'RouteTable.RouteTableId' --output text)
        aws ec2 create-route --route-table-id "$rtb_id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id"
        echo "Created new route table $rtb_id with default route to IGW"
    else
        echo "Found existing route table $rtb_id with default route to IGW"
    fi

    # Associate the route table with the subnet
    aws ec2 associate-route-table --route-table-id "$rtb_id" --subnet-id "$subnet_id"
    echo "Associated route table $rtb_id with subnet $subnet_id"

    # Enable auto-assign public IP on the subnet
    aws ec2 modify-subnet-attribute --subnet-id "$subnet_id" --map-public-ip-on-launch
    echo "Enabled auto-assign public IP on subnet $subnet_id"

    # Enable DNS hostnames on the VPC
    aws ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
    echo "Enabled DNS hostnames on VPC $vpc_id"
}

generate_random_password() {
    local upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c1)
    local lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c1)
    local digit=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c1)
    local rest=$(LC_ALL=C tr -dc 'A-Za-z0-9!@%^*_+=-' < /dev/urandom | head -c13)

    local password="$upper$lower$digit$rest"

    # Shuffle the result to avoid predictable structure
    echo "$password" | fold -w1 | shuf | tr -d '\n'
}

check_and_generate_random_passwords() {
    local vars=("cmapi_key" "pcs_pass" "admin_pass" "maxscale_pass" "repli_pass" "cej_pass")

    for var_name in "${vars[@]}"; do
        local current_val
        current_val=$(get_current_var_value "$var_name")

        if [[ "$current_val" == "<random>" ]]; then
            if [[ "$(ask_boolean "$var_name" "Generate random value for $var_name?" "true")" == "true" ]]; then
                local generated
                generated=$(generate_random_password)
                set_var_value "$var_name" "$generated" "true"
                echo "$var_name set to a secure random value"
            else
                echo "Skipping generation for $var_name"
            fi
        fi
    done
}

handle_additional_tags() {
    echo ""
    echo "Checking for required 'additional_tags' in terraform.tfvars..."

    if grep -q '^additional_tags *=' terraform.tfvars; then
        echo ""
        echo "'additional_tags' already exists in terraform.tfvars:"
        awk '/^additional_tags *= *\{/ {flag=1; print; next} /^\}/ {print; flag=0} flag' terraform.tfvars
        echo ""
        echo "You can edit these tags manually in terraform.tfvars if needed."
        return
    fi

    echo ""
    warn "'additional_tags' is not set."
    echo "If these tags are missing, security will automatically shut down your instance after some time."
    echo "Once the instance is stopped, its IP will change, breaking automatic connections."
    echo "Eventually, the instance and all associated data may be deleted."
    echo ""

    read -p "Enter your name for the 'owner' tag: " tag_owner
    read -p "Enter description for this cluster: " tag_description
    read -p "Enter expiration date (e.g., 2025-12-31): " tag_expiration

    echo "" >> terraform.tfvars
    {
        echo "additional_tags = {"
        echo "  owner       = \"$tag_owner\""
        echo "  description = \"$tag_description\""
        echo "  expiration  = \"$tag_expiration\""
        echo "}"
    } >> terraform.tfvars

    CHANGELOG+=("Added 'additional_tags': owner ($tag_owner), description ($tag_description), expiration ($tag_expiration)")
}

# Run

# Check if we're running under Bash
if [ -z "$BASH_VERSION" ]; then
  echo "ERROR: This script must be run with Bash, not sh or zsh."
  echo "Try running:"
  echo "  bash ./kickstart.sh"
  exit 1
fi

# Check Bash version
BASH_MAJOR_VERSION=${BASH_VERSINFO[0]}
if (( BASH_MAJOR_VERSION < 4 )); then
  echo "ERROR: Bash version 4 or higher is required (you are using Bash $BASH_VERSION)."
  echo "On macOS, install newer Bash with Homebrew:"
  echo "  brew install bash"
  echo "Then run this script with:"
  echo "  /opt/homebrew/bin/bash ./kickstart.sh"
  exit 1
fi

# Check if AWS CLI is installed, if not -- install it
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found, installing it now..."
    install_aws_cli
else
    # AWS CLI is installed, check the version
    aws_version=$(aws --version 2>&1)
    echo "Found AWS CLI: $aws_version"
    # Check if it's version 1.x
    if [[ "$aws_version" =~ aws-cli/1\. ]]; then
        echo ""
        echo "ERROR: AWS CLI version 1 detected."
        echo "This script requires AWS CLI v2."
        echo ""
        echo "Please uninstall AWS CLI v1. After uninstalling, run this script again to install AWS CLI v2 automatically."
        echo ""
        exit 1
    fi

    echo "AWS CLI version check passed. Continuing..."
fi

# If terraform.tfvars is not present, create it
if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars file..."
    cp .tfvars.sample terraform.tfvars
    echo ""
fi

echo "Filling terraform.tfvars with values..."
# If some variable is already set in terraform.tfvars, show it as default value

echo -e "\n\n"
note "AWS region we use in this script is $AWS_REGION, please use it everywhere\n\n"

if aws sts get-caller-identity >/dev/null 2>&1; then
    echo "User is already authenticated with AWS CLI"
    aws configure list
    show_aws_identity

    # If terraform.tfvars already specifies aws_profile, offer to switch to it immediately
    tfvars_profile=$(get_current_var_value "aws_profile")
    if [[ -n "$tfvars_profile" ]]; then
        # Check that profile exists locally
        if aws configure list-profiles | grep -qx "$tfvars_profile"; then
            if [[ "$(ask_boolean switch_to_tfvars_profile_start \
                "Detected aws_profile=\"$tfvars_profile\" in terraform.tfvars. Switch to it now?" \
                "true")" == "true" ]]; then
                echo "Using profile: $tfvars_profile"
                ensure_profile_credentials "$tfvars_profile"
                echo "Profile selection completed. Proceeding to sync credentials..."
            else
                reauth=$(ask_boolean "reauthenticate" "Do you want to re-authenticate or switch AWS profile?" "false")
                if [[ "$reauth" == "true" ]]; then
                    select_or_create_aws_profile
                    echo "Profile selection completed. Proceeding to sync credentials..."
                fi
            fi
        else
            # tfvars references a non-existing local profile; fall back to regular prompt
            reauth=$(ask_boolean "reauthenticate" "Do you want to re-authenticate or switch AWS profile?" "false")
            if [[ "$reauth" == "true" ]]; then
                select_or_create_aws_profile
                echo "Profile selection completed. Proceeding to sync credentials..."
            fi
        fi
    else
        reauth=$(ask_boolean "reauthenticate" "Do you want to re-authenticate or switch AWS profile?" "false")
        if [[ "$reauth" == "true" ]]; then
            select_or_create_aws_profile
            echo "Profile selection completed. Proceeding to sync credentials..."
        fi
    fi
else
    echo "User is not authenticated with AWS CLI yet"
    select_or_create_aws_profile
    echo "Profile selection completed. Proceeding to sync credentials..."
fi
echo ""

sync_terraform_vars_with_aws_credentials

choose_distro
echo ""

note "The 'deployment_prefix' variable is used to uniquely identify your cluster resources."
note "The default prefix 'testing' can cause conflicts with other clusters if not changed."
note "If Sentry is enabled, this prefix is used to create a Sentry environment name."
propose_change_value "deployment_prefix" false "Enter a unique prefix for this deployment"

echo ""
note "You can set a custom MariaDB Server/ColumnStore version via cs_package_manager_custom_version."
note "Example for CI/dev builds:   dev stable-23.10 cron/1443"
note "Example for Enterprise:      enterprise 10.6.12-8"
propose_change_value "cs_package_manager_custom_version" false "Enter custom version for cs_package_manager (leave blank for default)"
echo ""

# Handle follow-ups when a custom version is set
cv=$(get_current_var_value "cs_package_manager_custom_version")
if [ -n "$cv" ]; then
    if [[ "$cv" =~ ^dev[[:space:]] ]]; then
        ddk=$(get_current_var_value "dev_drone_key")
        if [ -z "$ddk" ]; then
            warn "You selected a dev/CI build but 'dev_drone_key' is not set. You won't be able to use CI builds without it."
        fi
    fi

    # If a custom version is set and mariadb_rpms_path is not set, set it implicitly
    cur_pkgs_path=$(get_current_var_value "mariadb_rpms_path")
    if [ -z "$cur_pkgs_path" ]; then
        set_var_value "mariadb_rpms_path" "/tmp/pkgs"
        note "Set 'mariadb_rpms_path' to '/tmp/pkgs' because a custom version was specified."
    fi
fi

check_or_choose_aws_key_pair

create_shared_efs=$(ask_boolean "create_shared_efs" "Do you want to create a EFS volume that is shared between hosts?" "$(get_current_var_value "create_shared_efs" "false")")
set_var_value "create_shared_efs" "$create_shared_efs"

if [ "$create_shared_efs" == "false" ]; then
    echo "Shared EFS creation is disabled."
    set_var_value "shared_efs_include_dev_host" "false"
    echo ""
else
    cloud_env=$(detect_cloud_environment)
    echo "Detected cloud environment: $cloud_env"
    if [ "$cloud_env" != "aws" ]; then
        warn "This host is not running in AWS. You cannot create a shared EFS volume between this host and the cluster nodes."
        echo "We can still create shared EFS between the cluster nodes, but it will not be accessible from this host."

        echo "Disabling shared EFS for dev host..."
        set_var_value "shared_efs_include_dev_host" "false"
    else
        host_region=$(get_this_host_region)
        echo "Dev host AWS region: $host_region"
        if [ -n "$host_region" ] && [ "$host_region" != "$AWS_REGION" ]; then
            warn "This host is running in AWS region $host_region. For this script to work correctly, this host must be in $AWS_REGION AWS region"
            echo "Disabling shared EFS for dev host..."
            set_var_value "shared_efs_include_dev_host" "false"
        else
            cur_val_include_dev_host=$(get_current_var_value "shared_efs_include_dev_host" "true")
            if [[ "$(ask_boolean shared_efs_include_dev_host 'Do you want to include (this) dev host in the shared EFS volume setup? This allows you to share code with the cluster nodes to build MCS with your changes' "$cur_val_include_dev_host")" == "true" ]]; then
                set_var_value "shared_efs_include_dev_host" "true"
                propose_change_value "shared_efs_mount_point" false "Mount point for shared EFS volume"
            else
                echo "Disabling shared EFS for dev host..."
                set_var_value "shared_efs_include_dev_host" "false"
            fi
        fi
    fi
fi
echo ""

propose_change_value "mariadb_enterprise_token" true "Get MariaDB Enterprise token from https://mariadb.com/downloads/token"
echo ""

cur_use_s3=$(get_current_var_value "use_s3" "false")
use_s3=$(ask_boolean "use_s3" "Do you want to use S3 in MCS setup?" "$cur_use_s3")
set_var_value "use_s3" "$use_s3"
echo ""

check_or_choose_vpc_and_sg
# Ensure the subnet is public
final_subnet_id=$(get_current_var_value "aws_subnet")
if [ -n "$final_subnet_id" ]; then
    if [ "$(is_subnet_public "$final_subnet_id")" != "public" ]; then
        echo "Subnet $final_subnet_id is not public. Making it public..."
        make_subnet_public "$final_subnet_id"
        echo "Subnet $final_subnet_id is now public."
    else
        echo "Subnet $final_subnet_id is already public."
    fi
fi

propose_change_value "num_columnstore_nodes" false "Number of ColumnStore nodes in the cluster"
propose_change_value "num_maxscale_instances" false "Number of MaxScale nodes in the cluster (at least 1)"

propose_change_value "aws_mariadb_instance_size"

# Optional Sentry DSN for CMAPI
cur_sentry_dsn=$(get_current_var_value "sentry_dsn" "")
read -p "Enter Sentry DSN to configure in CMAPI (leave empty to skip) ['${cur_sentry_dsn}']: " new_sentry_dsn
if [ -n "$new_sentry_dsn" ]; then
    set_var_value "sentry_dsn" "$new_sentry_dsn" true
elif [ -n "$cur_sentry_dsn" ]; then
    # keep existing
    set_var_value "sentry_dsn" "$cur_sentry_dsn" true
fi

propose_change_value "columnstore_node_root_block_size" false "Number of GB for EBS root storage on columnstore nodes"

handle_additional_tags

check_and_generate_random_passwords

# Show summary of changes made during this run
if [ "${#CHANGELOG[@]}" -gt 0 ]; then
    echo ""
    in_green "=== Summary of changes made ==="
    for change in "${CHANGELOG[@]}"; do
        echo "- $change"
    done
    echo ""
else
    in_green "No changes were made during this run."
fi