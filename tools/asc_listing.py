"""Push store listing (all locales), URLs and copyright to App Store Connect."""
import json, sys
sys.path.insert(0, "tools")
from asc_pricing import call, get_all, BUNDLE
from store_listing import LISTINGS, desc, PRIVACY, SUPPORT, MARKETING, COPYRIGHT

def upsert(kind, existing, loc, attrs, parent_rel, parent_type, parent_id):
    if loc in existing:
        r = call("PATCH", f"/v1/{kind}/{existing[loc]}", data=json.dumps(
            {"data": {"type": kind, "id": existing[loc], "attributes": attrs}}))
    else:
        r = call("POST", f"/v1/{kind}", data=json.dumps(
            {"data": {"type": kind, "attributes": {"locale": loc, **attrs},
                      "relationships": {parent_rel: {"data": {"type": parent_type, "id": parent_id}}}}}))
    return r.status_code, (r.text[:300] if r.status_code >= 300 else "")

app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]
print("App", app["id"], "primary locale", app["attributes"].get("primaryLocale"))

infos = get_all(f"/v1/apps/{app['id']}/appInfos")
info = next((i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_INFO")), infos[0])
print("appInfo", info["id"], info["attributes"].get("appStoreState") or info["attributes"].get("state"))
r = call("GET", f"/v1/appInfos/{info['id']}/primaryCategory").json()
print("primary category:", (r.get("data") or {}).get("id"))
if (r.get("data") or {}).get("id") != "WEATHER":
    rr = call("PATCH", f"/v1/appInfos/{info['id']}", data=json.dumps({"data": {"type": "appInfos", "id": info["id"],
        "relationships": {"primaryCategory": {"data": {"type": "appCategories", "id": "WEATHER"}}}}}))
    print("set category WEATHER:", rr.status_code, rr.text[:200] if rr.status_code >= 300 else "")

existing = {l["attributes"]["locale"]: l["id"] for l in get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")}
for loc, d in LISTINGS.items():
    code, err = upsert("appInfoLocalizations", existing, loc,
                       {"name": d["name"], "subtitle": d["subtitle"], "privacyPolicyUrl": PRIVACY},
                       "appInfo", "appInfos", info["id"])
    print(f"info  {loc:6} {code} {err}")

vers = get_all(f"/v1/apps/{app['id']}/appStoreVersions", {"filter[platform]": "IOS"})
ver = next(v for v in vers if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"))
print("version", ver["attributes"]["versionString"], ver["attributes"]["appStoreState"])
rr = call("PATCH", f"/v1/appStoreVersions/{ver['id']}", data=json.dumps(
    {"data": {"type": "appStoreVersions", "id": ver["id"], "attributes": {"copyright": COPYRIGHT}}}))
print("copyright:", rr.status_code, rr.text[:200] if rr.status_code >= 300 else COPYRIGHT)

existing = {l["attributes"]["locale"]: l["id"] for l in get_all(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")}
for loc, d in LISTINGS.items():
    code, err = upsert("appStoreVersionLocalizations", existing, loc,
                       {"description": desc(d["t"]), "keywords": d["keywords"], "promotionalText": d["promo"],
                        "supportUrl": SUPPORT, "marketingUrl": MARKETING},
                       "appStoreVersion", "appStoreVersions", ver["id"])
    print(f"store {loc:6} {code} {err}")
