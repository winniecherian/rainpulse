"""Report (and with 'fix', remove) introductory offers on monthly plans."""
import sys, json
sys.path.insert(0, "tools")
from asc_pricing import call, get_all, BUNDLE
fix = len(sys.argv) > 1 and sys.argv[1] == "fix"
app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]
for g in get_all(f"/v1/apps/{app['id']}/subscriptionGroups"):
    for s in get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions"):
        pid = s["attributes"]["productId"]
        offers = get_all(f"/v1/subscriptions/{s['id']}/introductoryOffers", {"limit": 200})
        modes = {}
        for o in offers:
            k = f"{o['attributes'].get('offerMode')}/{o['attributes'].get('duration')}"
            modes[k] = modes.get(k, 0) + 1
        print(pid, "intro offers:", len(offers), modes)
        if fix and pid.endswith(".monthly") and offers:
            codes = {}
            for o in offers:
                r = call("DELETE", f"/v1/subscriptionIntroductoryOffers/{o['id']}")
                codes[r.status_code] = codes.get(r.status_code, 0) + 1
                if r.status_code >= 300 and codes[r.status_code] == 1: print("   err", r.status_code, r.text[:300])
            print("   delete results:", codes)
            left = get_all(f"/v1/subscriptions/{s['id']}/introductoryOffers", {"limit": 200})
            print("   remaining:", len(left))
