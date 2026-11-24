"""List signing certificates on the developer account (read-only)."""
import sys
sys.path.insert(0, "tools")
from asc_pricing import get_all
certs = get_all("/v1/certificates", {"limit": 200})
print("total certificates:", len(certs))
for c in sorted(certs, key=lambda c: (c["attributes"].get("certificateType", ""), c["attributes"].get("expirationDate", ""))):
    a = c["attributes"]
    print(f'{c["id"]}  {a.get("certificateType")}  {a.get("displayName") or a.get("name")}  expires {a.get("expirationDate", "")[:10]}  activated={a.get("activated")}')
