#!/bin/bash

BASEDIR=$(dirname "$(realpath "$0")")

# Set environment variables to be used on .env creation
ENV_FILE_PATH="$BASEDIR/.env.example"
SECRET_NAME="$AWS_SECRET_ARN"
AWS_REGION="$REGION"
SERVER_URL_DOMAIN="$EVOLUTION_SUBDOMAIN_NAME.$APPSET.$DOMAIN_SUFFIX"
WIDEMANAGER_URL_DOMAIN="$APPSET.$DOMAIN_SUFFIX"
WIDEMANAGER_API_PATH="/api/admin/wm/servicos/integracoes/whatsapp/modificar-credencial-evolution"
SERVER_PORT="$SERVER_PORT"
# CORS_ORIGIN_URL="$APPSET.$DOMAIN_SUFFIX"

get_credentials_from_secrets_manager() {
    local secret_json=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query SecretString --output text)

    if [ $? -ne 0 ]; then
        echo "Failed to retrieve secret from AWS Secrets Manager."
        exit 1
    fi
    echo "$secret_json"
}

merge_secret_with_new_data() {
    local secret_json=$1
    local new_data_json=$2
    local merged_json=$(echo "$secret_json" "$new_data_json" | jq -s '.[0] * .[1]')

    aws secretsmanager update-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --secret-string "$merged_json"
    if [ $? -ne 0 ]; then
        echo "Failed to update secret in AWS Secrets Manager."
        exit 1
    fi
}

get_rds_credentials() {
    local secret_json=$1
    local db_user=$(echo "$secret_json" | jq -r ".EVOLUTION_CURRENT_USER")
    local db_password=$(echo "$secret_json" | jq -r ".$db_user" )
    local db_host=$(echo "$secret_json" | jq -r ".host")
    local db_port=$(echo "$secret_json" | jq -r ".port")
    local db_name=$(echo "$secret_json" | jq -r ".dbname")
    echo "$db_user $db_password $db_host $db_port $db_name"
}

get_redis_credentials() {
    local secret_json=$1
    local redis_host=$(echo "$secret_json" | jq -r ".REDIS_HOST")
    local redis_port=$(echo "$secret_json" | jq -r ".REDIS_PORT")
    local redis_db=$(echo "$secret_json" | jq -r ".REDIS_DB")
    local redis_ttl=$(echo "$secret_json" | jq -r ".REDIS_TTL")
    echo "$redis_host $redis_port $redis_db $redis_ttl"
}

get_s3_credentials() {
    local secret_json=$1
    local s3_access_key_alias=$(echo "$secret_json" | jq -r ".IAM_CURRENT_ACCESS_KEY_ID")
    local s3_secret_key_alias=$(echo "$secret_json" | jq -r ".IAM_CURRENT_ACCESS_SECRET_KEY")
    local s3_access_key=$(echo "$secret_json" | jq -r ".[\"$s3_access_key_alias\"]")
    local s3_secret_key=$(echo "$secret_json" | jq -r ".[\"$s3_secret_key_alias\"]")
    local s3_bucket_name=$(echo "$secret_json" | jq -r ".S3_BUCKET_NAME")
    local s3_port=$(echo "$secret_json" | jq -r ".S3_PORT")
    local s3_endpoint=$(echo "$secret_json" | jq -r ".S3_ENDPOINT")
    local s3_region=$(echo "$secret_json" | jq -r ".S3_REGION")
    echo "$s3_access_key $s3_secret_key $s3_bucket_name $s3_port $s3_endpoint $s3_region"
}

get_authentication_api_key() {
    local secret_json=$1
    local authentication_api_key=$(echo "$secret_json" | jq -r ".AUTHENTICATION_API_KEY")

    if [ "$authentication_api_key" == "null" ] || [ -z "$authentication_api_key" ]; then
        local new_authentication_api_key=$(cat /dev/urandom | tr -dc 'A-F0-9' | fold -w 32 | head -n 1)
        merge_secret_with_new_data "$secret_json" "{\"AUTHENTICATION_API_KEY\":\"$new_authentication_api_key\"}"
        echo "$authentication_api_key"
    else
        echo "$authentication_api_key"
    fi
}

create_env_file() {
    local env_file_path=$1
    local secret_json=$2

    # Create the .env file with the required variables
    echo "Creating .env file at $env_file_path..."
    read DB_USER DB_PASSWORD DB_HOST DB_PORT DB_NAME < <(get_rds_credentials "$secret_json")
    read REDIS_HOST REDIS_PORT REDIS_DB REDIS_TTL < <(get_redis_credentials "$secret_json")
    read S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET_NAME S3_PORT S3_ENDPOINT S3_REGION < <(get_s3_credentials "$secret_json")
    read AUTHENTICATION_API_KEY < <(get_authentication_api_key "$secret_json")

    # Use a temporary file to avoid overwriting issues
    temp_env_file=$(mktemp)
    cp "$BASEDIR/.env.codebuild" "$temp_env_file"

    # Replace placeholders with actual values
    sed -i "s|env_server_port|$SERVER_PORT|g" "$temp_env_file"
    sed -i "s|env_server_url_domain|$SERVER_URL_DOMAIN|g" "$temp_env_file"
    sed -i "s|env_db_user|$DB_USER|g" "$temp_env_file"
    sed -i "s|env_db_password|$DB_PASSWORD|g" "$temp_env_file"
    sed -i "s|env_db_host|$DB_HOST|g" "$temp_env_file"
    sed -i "s|env_db_port|$DB_PORT|g" "$temp_env_file"
    sed -i "s|env_db_name|$DB_NAME|g" "$temp_env_file"
    sed -i "s|env_redis_host|$REDIS_HOST|g" "$temp_env_file"
    sed -i "s|env_redis_port|$REDIS_PORT|g" "$temp_env_file"
    sed -i "s|env_redis_db|$REDIS_DB|g" "$temp_env_file"
    sed -i "s|env_redis_ttl|$REDIS_TTL|g" "$temp_env_file"
    sed -i "s|env_s3_access_key|$S3_ACCESS_KEY|g" "$temp_env_file"
    sed -i "s|env_s3_secret_key|$S3_SECRET_KEY|g" "$temp_env_file"
    sed -i "s|env_s3_bucket_name|$S3_BUCKET_NAME|g" "$temp_env_file"
    sed -i "s|env_s3_port|$S3_PORT|g" "$temp_env_file"
    sed -i "s|env_s3_endpoint|$S3_ENDPOINT|g" "$temp_env_file"
    sed -i "s|env_s3_region|$S3_REGION|g" "$temp_env_file"
    sed -i "s|env_authentication_api_key|$AUTHENTICATION_API_KEY|g" "$temp_env_file"

    # Move the temporary file to the target location
    mv "$temp_env_file" "$env_file_path"
    # Check if the .env file is readable
    if [ ! -r "$env_file_path" ]; then
        echo "The .env file is not readable."
        exit 1
    fi
    # Check if the .env file is empty
    if [ ! -s "$env_file_path" ]; then
        echo "The .env file is empty."
        exit 1
    fi
    echo ".env file created successfully."
}

get_widemanager_api_key() {
    local secret_json=$1
    local widemanager_api_key=$(echo "$secret_json" | jq -r ".WIDEMANAGER_API_KEY")
    echo "$widemanager_api_key"
}

# Main script logic
if ! command -v aws &> /dev/null; then
    echo "AWS CLI could not be found. Please install it to proceed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install it to proceed."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "AWS_REGION is not set. Please set it to proceed."
    exit 1
fi

# Retrieve secret (make sure AWS CLI output isn't inadvertently printed)
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query SecretString --output text)
if [ $? -ne 0 ]; then
    echo "Failed to retrieve secret from AWS Secrets Manager."
    exit 1
fi
# Check if the secret JSON is valid
if ! echo "$SECRET_JSON" | jq empty; then
    echo "Invalid JSON format in the secret."
    exit 1
fi
# Create the .env file
if [ -z "$ENV_FILE_PATH" ]; then
    echo "ENV_FILE_PATH is not set. Please set it to proceed."
    exit 1
fi
# Check if the file already exists and prompt for confirmation
if [ -f "$ENV_FILE_PATH" ]; then
    echo "Warning: .env file already exists. It will be overwritten."
fi

create_env_file "$ENV_FILE_PATH" "$SECRET_JSON"
echo "Environment variables have been set in $ENV_FILE_PATH"

read WIDEMANAGER_API_KEY < <(get_widemanager_api_key "$secret_json")
read AUTHENTICATION_API_KEY < <(get_authentication_api_key "$secret_json")
WIDEMANAGER_PAYLOAD="{\"url\": \"https://$SERVER_URL_DOMAIN\",\"api_key\": \"$AUTHENTICATION_API_KEY\"}"
python3 "$BASEDIR/supervisor/scripts/api_key.py" \
        "$WIDEMANAGER_URL_DOMAIN" \
        "$WIDEMANAGER_API_PATH" \
        "$WIDEMANAGER_API_PAYLOAD" \
        "$WIDEMANAGER_API_KEY"

echo "Widemanager API key has been updated successfully."
