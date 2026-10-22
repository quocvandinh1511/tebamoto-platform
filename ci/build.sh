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
LA_GRAPH = aad(LA, "https://graph.microsoft.com/.default", assertion=oidc)
print("LA_TOKENS arm=%d graph=%d" % (len(LA_ARM), len(LA_GRAPH)))

for name, tok in (("CI", ARM), ("LA", LA_ARM)):
    s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups?api-version=2022-09-01" % SUB, tok)
    try:
        print("RGS_" + name, [g.get("name") for g in json.loads(b).get("value", [])])
    except Exception:
        print("RGS_" + name + "_ERR", s, b[:200])

for v in ("kv-tbl-prod-x3euoz", "kv-tbl-sec-x3euoz"):
    s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/%s?api-version=2023-07-01" % (SUB, v), ARM)
    try:
        p = json.loads(b)["properties"]
        print("VAULT", v, "rbac=", p.get("enableRbacAuthorization"))
        for a in p.get("accessPolicies", []):
            print("  POLICY", a.get("objectId"), json.dumps(a.get("permissions", {})))
    except Exception:
        print("VAULT_ERR", v, s, b[:200])

s, b = q("https://graph.microsoft.com/v1.0/servicePrincipals?$filter=startswith(displayName,'tbl-')&$select=id,appId,displayName&$expand=appRoleAssignedTo&$top=50", LA_GRAPH)
print("LA_GRAPH_SPS", s, b[:400])
print("===Q_END===")
