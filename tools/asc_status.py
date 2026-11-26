"""Read-only launch readiness report from App Store Connect."""
import json, sys
sys.path.insert(0, "tools")
from asc_pricing import call, get_all, BUNDLE
def g(p, params=None):
    r = call("GET", p, params=params); return r.json() if r.status_code < 300 else {"error": r.status_code, "text": r.text[:300]}
app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]; aid = app["id"]
a = app["attributes"]
print("APP", aid, a.get("name"), "| contentRights:", a.get("contentRightsDeclaration"), "| primaryLocale:", a.get("primaryLocale"))
for v in get_all(f"/v1/apps/{aid}/appStoreVersions"):
    va = v["attributes"]; print("VERSION", va.get("versionString"), va.get("appStoreState"), va.get("appVersionState"), "release:", va.get("releaseType"), "earliest:", va.get("earliestReleaseDate"))
    b = g(f"/v1/appStoreVersions/{v['id']}/build").get("data")
    print("  build attached:", b and b["attributes"].get("version"), b and b["attributes"].get("processingState"), "nonExemptEncryption:", b and b["attributes"].get("usesNonExemptEncryption"))
    rd = g(f"/v1/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
    print("  review detail:", rd and {k: rd["attributes"].get(k) for k in ("contactFirstName","contactEmail","contactPhone","demoAccountRequired","notes")})
    ph = g(f"/v1/appStoreVersions/{v['id']}/appStoreVersionPhasedRelease").get("data")
    print("  phased release:", ph and ph["attributes"])
for i in get_all(f"/v1/apps/{aid}/appInfos"):
    ia = i["attributes"]; print("APPINFO", ia.get("appStoreState") or ia.get("state"), "ageRating:", ia.get("appStoreAgeRating"), "kids:", ia.get("kidsAgeBand"))
    ad = g(f"/v1/appInfos/{i['id']}/ageRatingDeclaration").get("data")
    print("  ageRatingDeclaration set:", bool(ad))
builds = get_all(f"/v1/builds", {"filter[app]": aid, "sort": "-uploadedDate", "limit": 3})
for b in builds[:3]: print("BUILD", b["attributes"].get("version"), b["attributes"].get("processingState"), b["attributes"].get("uploadedDate"), "expired:", b["attributes"].get("expired"))
for grp in get_all(f"/v1/apps/{aid}/subscriptionGroups"):
    print("SUBGROUP", grp["attributes"].get("referenceName"))
    for s in get_all(f"/v1/subscriptionGroups/{grp['id']}/subscriptions"):
        sa = s["attributes"]; print("  SUB", sa.get("productId"), sa.get("state"), sa.get("familySharable"))
av = g(f"/v1/apps/{aid}/appAvailabilityV2")
print("AVAILABILITY", json.dumps(av.get("data", {}).get("attributes", av))[:200])
print("PRICE SCHEDULE", json.dumps(g(f"/v1/apps/{aid}/appPriceSchedule").get("data", {}).get("id")))
