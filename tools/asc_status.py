"""Read-only: why subscriptions show MISSING_METADATA, and app availability."""
import json, sys
sys.path.insert(0, "tools")
from asc_pricing import call, get_all, BUNDLE
def g(p, params=None):
    r = call("GET", p, params=params); return r.json() if r.status_code < 300 else {"error": r.status_code, "text": r.text[:200]}
app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]; aid = app["id"]
for grp in get_all(f"/v1/apps/{aid}/subscriptionGroups"):
    gl = get_all(f"/v1/subscriptionGroups/{grp['id']}/subscriptionGroupLocalizations")
    print("GROUP localizations:", [(l["attributes"]["locale"], l["attributes"].get("name"), l["attributes"].get("state")) for l in gl])
    for s in get_all(f"/v1/subscriptionGroups/{grp['id']}/subscriptions"):
        sid = s["id"]; sa = s["attributes"]
        locs = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        shot = g(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot").get("data")
        prices = g(f"/v1/subscriptions/{sid}/prices", {"limit": 1})
        avail = g(f"/v1/subscriptions/{sid}/subscriptionAvailability").get("data")
        print("SUB", sa["productId"], sa.get("state"), "period:", sa.get("subscriptionPeriod"), "reviewNote:", bool(sa.get("reviewNote")),
              "| locs:", len(locs), [l["attributes"].get("state") for l in locs][:3],
              "| reviewScreenshot:", bool(shot), "| prices:", len(prices.get("data", [])) if "data" in prices else prices,
              "| availability:", bool(avail))
r = call("GET", f"/v1/apps/{aid}", params={"include": "appAvailabilityV2", "fields[apps]": "appAvailabilityV2"})
print("APP AVAILABILITY rel:", r.status_code, r.text[:400])
