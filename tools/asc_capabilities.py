"""List the App ID's capabilities; with 'icloud', enable iCloud (CloudKit) on the main app's App ID."""
import sys, json
sys.path.insert(0, "tools")
from asc_pricing import get_all, call, BUNDLE
mode = sys.argv[1] if len(sys.argv) > 1 else "list"
ids = get_all("/v1/bundleIds", {"filter[identifier]": BUNDLE, "limit": 200})
bid = next(b for b in ids if b["attributes"]["identifier"] == BUNDLE)
print("bundle", BUNDLE, bid["id"], bid["attributes"].get("platform"))
caps = get_all(f"/v1/bundleIds/{bid['id']}/bundleIdCapabilities")
for c in caps:
    print("  cap", c["attributes"].get("capabilityType"), json.dumps(c["attributes"].get("settings"))[:200])
if mode == "icloud" and not any(c["attributes"].get("capabilityType") == "ICLOUD" for c in caps):
    body = {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "ICLOUD", "settings": [
        {"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid["id"]}}}}}
    r = call("POST", "/v1/bundleIdCapabilities", json=body)
    print("enable ICLOUD:", r.status_code, r.text[:400])
