"""Signing certificates on the developer account.
  list              show all certificates (read-only)
  snapshot FILE     save the current certificate IDs to FILE
  revoke-new FILE   revoke DEVELOPMENT certificates created since FILE was saved (this CI run's throwaway)
  revoke-ci         revoke DEVELOPMENT certificates named "Created via API" (old CI throwaways)
"""
import sys, json
sys.path.insert(0, "tools")
from asc_pricing import get_all, call

def certs():
    return get_all("/v1/certificates", {"limit": 200})

def revoke(c):
    a = c["attributes"]
    r = call("DELETE", f"/v1/certificates/{c['id']}")
    print(f"revoke {c['id']} {a.get('certificateType')} {a.get('displayName')}: HTTP {r.status_code}")

mode = sys.argv[1] if len(sys.argv) > 1 else "list"
if mode == "list":
    cs = certs(); print("total certificates:", len(cs))
    for c in sorted(cs, key=lambda c: (c["attributes"].get("certificateType", ""), c["attributes"].get("expirationDate", ""))):
        a = c["attributes"]
        print(f'{c["id"]}  {a.get("certificateType")}  {a.get("displayName") or a.get("name")}  expires {a.get("expirationDate", "")[:10]}')
elif mode == "snapshot":
    json.dump([c["id"] for c in certs()], open(sys.argv[2], "w")); print("saved")
elif mode == "revoke-new":
    before = set(json.load(open(sys.argv[2])))
    for c in certs():
        if c["id"] not in before and c["attributes"].get("certificateType") == "DEVELOPMENT":
            revoke(c)
elif mode == "revoke-ci":
    for c in certs():
        a = c["attributes"]
        if a.get("certificateType") == "DEVELOPMENT" and a.get("displayName") == "Created via API":
            revoke(c)
