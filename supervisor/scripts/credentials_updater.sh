#!/bin/bash

source utils.sh

BASEDIR=$(dirname "$(realpath "$0")")

SECRET_NAME="$AWS_SECRET_ARN"
AWS_REGION="$REGION"
# ENV_FILE="/evolution/.env"
ENV_FILE="$BASEDIR/.env"

export_env_vars_from_json() {
    local json_string="$1"
    if [ -z "$json_string" ]; then
        logerror "No JSON string provided to export_env_vars_from_json"
        exit 1
    fi
    while IFS='=' read -r key value; do
        # export "$key=$value"
        eval "$key=\"$value\""
    done < <(echo "$json_string" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
}

get_json_fields() {
    local secret_json=$1
    shift
    for field in "$@"; do
        local value=$(echo "$secret_json" | jq -r ".$field")
        if [ $? -ne 0 ]; then
            logerror "Failed to retrieve field $field from secret JSON."
            exit 1
        fi
        echo "$value"
    done
}

get_local_credential() {
    local field=$1
    local value=$(grep -E "^$field=" "$ENV_FILE" | cut -d '=' -f2-)
    if [ $? -ne 0 ]; then
        logerror "Failed to retrieve field $field from local .env file."
        exit 1
    fi
    echo "$value"
}

get_local_dsn() {
    local field=$1
    local value=$(grep -E "^$field=" "$ENV_FILE" | cut -d '=' -f2-)

    if [ $? -ne 0 ]; then
        logerror "Failed to retrieve field $field from local .env file."
        exit 1
    fi

    local dsn="$value"
    local dsn_no_proto="${dsn#*://}"
    local user_and_pass="${dsn_no_proto%@*}"
    local user="${user_and_pass%%:*}"
    local pass="${user_and_pass#*:}"
    local host_port_values="${dsn_no_proto#*@}"
    local host_and_port="${host_port_values%%/*}"
    local host="${host_and_port%%:*}"
    local port="${host_and_port#*:}"
    local db_and_schema="${host_port_values#*/}"
    local dbname="${db_and_schema%%\?*}"
    local schema="$(echo "$db_and_schema" | grep -o 'schema=[^&]*' | cut -d'=' -f2)"
    echo "$user $pass $host $port $dbname $schema"
}

# Main script logic
if ! command -v aws &> /dev/null; then
    logerror "AWS CLI could not be found. Please install it to proceed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    logerror "jq could not be found. Please install it to proceed."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    logerror "AWS_REGION is not set. Please set it to proceed."
    exit 1
fi

RESTART_APP="false"
AUTHENTICATION_API_KEY_CHANGED="false"
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query SecretString --output text)
if [ $? -ne 0 ]; then
    logerror "Failed to retrieve secret from AWS Secrets Manager."
    exit 1
fi
if ! echo "$SECRET_JSON" | jq empty; then
    logerror "Invalid JSON format in the secret."
    exit 1
fi

export_env_vars_from_json "$SECRET_JSON"

# RDS credentials
read DB_USER DB_PASS DB_HOST DB_PORT DB_NAME DB_SCHEMA < <(get_local_dsn "DATABASE_CONNECTION_URI")
if [ -z "$DB_USER" ]; then
    logerror "Failed to retrieve DB_USER from local .env file."
    exit 1
fi
if [ -z "$DB_PASS" ]; then
    logerror "Failed to retrieve DB_PASS from local .env file."
    exit 1
fi
if [ -z "$DB_HOST" ]; then
    logerror "Failed to retrieve DB_HOST from local .env file."
    exit 1
fi
if [ -z "$DB_PORT" ]; then
    logerror "Failed to retrieve DB_PORT from local .env file."
    exit 1
fi
if [ -z "$DB_NAME" ]; then
    logerror "Failed to retrieve DB_NAME from local .env file."
    exit 1
fi
if [ -z "$DB_SCHEMA" ]; then
    logerror "Failed to retrieve DB_SCHEMA from local .env file."
    exit 1
fi
sleep 1
if [ "$EVOLUTION_CURRENT_USER" != "$DB_USER" ]; then
    EVOLUTION_CURRENT_USER_PASS="${!EVOLUTION_CURRENT_USER}"
    loginfo "Updating .env file with new credentials..."
    loginfo "Setting new dsn for DATABASE_CONNECTION_URI"
    NEW_DATABASE_CONNECTION_URI="postgresql://$EVOLUTION_CURRENT_USER:$EVOLUTION_CURRENT_USER_PASS@$DB_HOST:$DB_PORT/$DB_NAME?schema=$DB_SCHEMA"
    sed -i "s|^DATABASE_CONNECTION_URI=.*|DATABASE_CONNECTION_URI=$NEW_DATABASE_CONNECTION_URI|" "$ENV_FILE"
    RESTART_APP="true"
    loginfo ".env file updated successfully."
else
    loginfo ".env file is already up to date (RDS credentials)."
fi

# S3 credentials
read S3_ACCESS_KEY < <(get_local_credential "S3_ACCESS_KEY")
if [ -z "$S3_ACCESS_KEY" ]; then
    logerror "Failed to retrieve S3_ACCESS_KEY from local .env file."
    exit 1
fi
read S3_SECRET_KEY < <(get_local_credential "S3_SECRET_KEY")
if [ -z "$S3_SECRET_KEY" ]; then
    logerror "Failed to retrieve S3_SECRET_KEY from local .env file."
    exit 1
fi
sleep 1
if [[ "${!IAM_CURRENT_ACCESS_KEY_ID}" != "$S3_ACCESS_KEY" || "${!IAM_CURRENT_ACCESS_SECRET_KEY}" != "$S3_SECRET_KEY" ]]; then
    IAM_ACCESS_KEY_ID="${!IAM_CURRENT_ACCESS_KEY_ID}"
    IAM_ACCESS_SECRET_KEY="${!IAM_CURRENT_ACCESS_SECRET_KEY}"
    loginfo "Updating .env file with new credentials..."
    loginfo "Setting new credential for S3_ACCESS_KEY"
    sed -i "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=$IAM_ACCESS_KEY_ID|" "$ENV_FILE"
    loginfo "Setting new credential for S3_SECRET_KEY"
    sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=$IAM_ACCESS_SECRET_KEY|" "$ENV_FILE"
    RESTART_APP="true"
    loginfo ".env file updated successfully."
else
    loginfo ".env file is already up to date (S3 credentials)."
fi

# API key
read LOCAL_AUTHENTICATION_API_KEY < <(get_local_credential "AUTHENTICATION_API_KEY")
if [ -z "$LOCAL_AUTHENTICATION_API_KEY" ]; then
    logerror "Failed to retrieve AUTHENTICATION_API_KEY from local .env file."
    exit 1
fi

if [[ "$AUTHENTICATION_API_KEY" != "$LOCAL_AUTHENTICATION_API_KEY" ]]; then
    loginfo "Updating .env file with new credentials..."
    loginfo "Setting new credential for AUTHENTICATION_API_KEY"
    sed -i "s|^AUTHENTICATION_API_KEY=.*|AUTHENTICATION_API_KEY=$AUTHENTICATION_API_KEY|" "$ENV_FILE"
    AUTHENTICATION_API_KEY_CHANGED="true"
    RESTART_APP="true"
    loginfo ".env file updated successfully."
else
    loginfo ".env file is already up to date (Evolution API key)."
fi

loginfo "All credentials are up to date."

if [ "$RESTART_APP" == "true" ]; then
    loginfo "Restarting the application..."
    supervisorctl restart evolution-api
    if [ $? -ne 0 ]; then
        logerror "Failed to restart the application."
        exit 1
    fi
    loginfo "Application restarted successfully."
else
    loginfo "No changes made to the .env file. No need to restart the application."
fi

if [ "$AUTHENTICATION_API_KEY_CHANGED" == "true" ]; then
    loginfo "Authentication API key has changed. Setting API key to Widemanager API..."
    WIDEMANAGER_API_PAYLOAD="{\"url\": \"https://$EVOLUTION_API_URL\",\"api_key\": \"$AUTHENTICATION_API_KEY\"}"
    python3 "$BASEDIR/api_key.py" \
            "$WIDEMANAGER_API_URL" \
            "$WIDEMANAGER_API_PATH" \
            "$WIDEMANAGER_API_PAYLOAD" \
            "$WIDEMANAGER_API_KEY"
    if [ $? -ne 0 ]; then
        logerror "Failed to set API key to Widemanager API."
        exit 1
    else
        loginfo "API key set to Widemanager API successfully."
    fi
else
    loginfo "No changes made to the AUTHENTICATION_API_KEY. No need to set API key to Widemanager API."
fi

loginfo "Credentials check completed successfully."
loginfo "Script completed successfully."

# Melhorias:
# - Adicionar logs para facilitar o debug
# Fragmentar o script:
    # Um que irá criar o .secret.json
        # Lẽ o secret para .secret.json.tmp, compara com o .secret.json e se estiver diferença irá ser movido para .secret.json
        # Executa o segundo script
    # Um que irá alterar o .env e dar reload na aplicação
