#!/bin/bash

source utils.sh

BASEDIR=$(dirname "$(realpath "$0")")

SECRET_NAME="$AWS_SECRET_ARN"
AWS_REGION="$REGION"

SECRET_JSON_FILE="$BASEDIR/.secret.json"
SECRET_JSON_TMP_FILE="$BASEDIR/.secret.json.tmp"
SCRIPT_TO_RUN="$BASEDIR/credentials_updater.sh"

get_credentials_from_secrets_manager() {
    local secret_json=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$AWS_REGION" --query SecretString --output text)
    local file_path="$1"

    if [ $? -ne 0 ]; then
        echo "Failed to retrieve secret from AWS Secrets Manager."
        exit 1
    fi
    echo "$secret_json" > $file_path
}

# Main script logic
if ! command -v jq &> /dev/null; then
    logerror "jq could not be found. Please install it to proceed."
    exit 1
fi
if [ -z "$AWS_REGION" ]; then
    logerror "AWS_REGION is not set. Please set it to proceed."
    exit 1
fi
if [ -z "$SECRET_NAME" ]; then
    logerror "AWS_SECRET_ARN is not set. Please set it to proceed."
    exit 1
fi

if [ -f "$SECRET_JSON_TMP_FILE" ]; then
    rm "$SECRET_JSON_TMP_FILE"
fi

if [ ! -f "$SECRET_JSON_FILE" ]; then
    get_credentials_from_secrets_manager "$SECRET_JSON_FILE"
    if ! jq empty "$SECRET_JSON_FILE" > /dev/null 2>&1; then
        logerror "Invalid JSON format in the $SECRET_JSON_FILE file."
        exit 1
    fi
    bash "$SCRIPT_TO_RUN"
    if [ $? -ne 0 ]; then
        logerror "Failed to run the credentials updater script."
        exit 1
    fi
    exit 0
fi

get_credentials_from_secrets_manager "$SECRET_JSON_TMP_FILE"
if ! jq empty "$SECRET_JSON_TMP_FILE" > /dev/null 2>&1; then
    logerror "Invalid JSON format in the $$SECRET_JSON_TMP_FILE file."
    exit 1
fi

if ! cmp -s "$SECRET_JSON_FILE" "$SECRET_JSON_TMP_FILE"; then
    loginfo "Credentials have changed, updating .env file..."
    bash "$SCRIPT_TO_RUN"
    if [ $? -ne 0 ]; then
        logerror "Failed to update credentials."
        rm "$SECRET_JSON_TMP_FILE"
        exit 1
    fi
    mv "$SECRET_JSON_TMP_FILE" "$SECRET_JSON_FILE"
    exit 0
else
    loginfo "Credentials have not changed, no update needed."
    rm "$SECRET_JSON_TMP_FILE"
    exit 0
fi


