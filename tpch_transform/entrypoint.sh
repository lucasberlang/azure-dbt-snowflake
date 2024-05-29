#!/bin/sh

echo "================================="
echo "Starting new job"

echo "Retrieving snowflake certificate"
kv_url="$ENV_KV_URL/secrets/$ENV_SNOW_SECRET"
token=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true -s | jq -r '.access_token')


curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true
curl "$kv_url/?api-version=2016-10-01"  -H "Authorization: Bearer $token" | jq -r ".value" > /snowflake_dbt.64

base64 -d /snowflake_dbt.64 > /snowflake_dbt.pem 

echo "Executing new job on DBT"

dbt run -t pro

echo " Finished"
echo "================================="
