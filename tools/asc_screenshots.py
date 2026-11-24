"""Upload store/screenshots/en/*.png to the en-US listing (6.9"/6.7" iPhone slot)."""
import json, sys, os, glob, hashlib, time
sys.path.insert(0, "tools")
import requests
from asc_pricing import call, get_all, BUNDLE

DISPLAY = "APP_IPHONE_67"
files = sorted(glob.glob("store/screenshots/en/*.png"))
app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]
ver = next(v for v in get_all(f"/v1/apps/{app['id']}/appStoreVersions", {"filter[platform]": "IOS"})
           if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")
locs = {l["attributes"]["locale"]: l["id"] for l in get_all(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")}
loc_id = locs["en-US"]
sets = get_all(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY), None)
if not sset:
    r = call("POST", "/v1/appScreenshotSets", data=json.dumps({"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}))
    print("create set", r.status_code, r.text[:300] if r.status_code >= 300 else "")
    sset = r.json()["data"]
for old in get_all(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots"):
    print("delete old", call("DELETE", f"/v1/appScreenshots/{old['id']}").status_code)
ids = []
for f in files:
    data = open(f, "rb").read()
    r = call("POST", "/v1/appScreenshots", data=json.dumps({"data": {"type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}}))
    if r.status_code >= 300:
        print("reserve fail", f, r.status_code, r.text[:300]); continue
    shot = r.json()["data"]
    for op in shot["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        pr = requests.request(op["method"], op["url"], data=part, headers=headers, timeout=120)
        if pr.status_code >= 300: print("part fail", pr.status_code, pr.text[:200])
    r = call("PATCH", f"/v1/appScreenshots/{shot['id']}", data=json.dumps({"data": {"type": "appScreenshots",
        "id": shot["id"], "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}))
    print("uploaded", os.path.basename(f), r.status_code, r.text[:200] if r.status_code >= 300 else "")
    ids.append(shot["id"])
r = call("PATCH", f"/v1/appScreenshotSets/{sset['id']}/relationships/appScreenshots",
         data=json.dumps({"data": [{"type": "appScreenshots", "id": i} for i in ids]}))
print("order", r.status_code)
time.sleep(20)
for s in get_all(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots"):
    st = s["attributes"].get("assetDeliveryState") or {}
    print(s["attributes"]["fileName"], st.get("state"), st.get("errors"))
