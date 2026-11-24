"""App Store Connect subscription pricing tool.
Usage: python3 tools/asc_pricing.py inspect | apply
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID
"""
import os, sys, time, json, jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
KEY_ID, ISSUER, P8 = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_P8"]
BUNDLE = os.environ.get("BUNDLE_ID", "com.neuralorbitx.rainpulse")

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})

S = requests.Session()
def call(method, path, **kw):
    for attempt in range(5):
        r = S.request(method, path if path.startswith("http") else BASE + path,
                      headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, timeout=60, **kw)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(5 * (attempt + 1)); continue
        return r
    return r

def get_all(path, params=None):
    out, url = [], path
    while url:
        r = call("GET", url, params=params if url == path else None)
        r.raise_for_status()
        j = r.json(); out += j["data"]; url = j.get("links", {}).get("next")
    return out

# Target US prices
TARGET = {
    "rainpulse.essential.monthly": 2.99, "rainpulse.essential.yearly": 19.99,
    "rainpulse.pro.monthly": 5.99, "rainpulse.pro.yearly": 34.99,
}
BAND_A = {"USA","CAN","GBR","IRL","FRA","DEU","ITA","ESP","PRT","NLD","BEL","LUX","AUT","CHE","LIE","DNK","SWE","NOR","FIN","ISL",
          "AUS","NZL","JPN","KOR","SGP","HKG","TWN","ARE","SAU","QAT","KWT","BHR","OMN","ISR","MLT","CYP","GRC","SVN","EST","MCO"}
BAND_C = {"IDN","PHL","VNM","PAK","BGD","EGY","NGA","KEN","BRA","COL","ARG","PER","LKA","NPL","GHA","TZA","UGA","MAR","DZA","TUN",
          "BOL","PRY","ECU","GTM","HND","NIC","SLV","KHM","LAO","MMR","MNG","UZB","KAZ","KGZ","TJK","ETH","ZWE","ZMB","MOZ","CMR",
          "SEN","CIV","MDG","MWI","RWA","AGO","NAM","BWA","JAM","DOM","UKR","AZE","ARM","GEO","MDA","BLR","IRQ","JOR","LBN","LBY","YEM"}
SKIP = {"IND"}   # India prices already set by hand
def band(t):
    if t in SKIP: return None
    if t in BAND_A: return 1.0
    if t in BAND_C: return 0.38
    return 0.60

def main(mode):
    apps = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})
    app = apps[0]; print("App", app["id"], app["attributes"]["name"])
    groups = get_all(f"/v1/apps/{app['id']}/subscriptionGroups")
    subs = []
    for g in groups:
        subs += get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions")
    for s in subs:
        a = s["attributes"]
        print(f"- {a['productId']} id={s['id']} state={a.get('state')} period={a.get('subscriptionPeriod')} family={a.get('familySharable')}")
        prices = get_all(f"/v1/subscriptions/{s['id']}/prices", {"include": "subscriptionPricePoint,territory", "limit": 200})
        print(f"    {len(prices)} price records")
        offers = get_all(f"/v1/subscriptions/{s['id']}/introductoryOffers", {"limit": 200})
        modes = {}
        for o in offers:
            k = (o["attributes"].get("offerMode"), o["attributes"].get("duration"))
            modes[k] = modes.get(k, 0) + 1
        print("    intro offers:", modes)

    if mode != "apply":
        # Show US price points near targets
        for s in subs:
            pid = s["attributes"]["productId"]
            if pid not in TARGET: continue
            pts = get_all(f"/v1/subscriptions/{s['id']}/pricePoints", {"filter[territory]": "USA", "limit": 200})
            near = sorted(pts, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - TARGET[pid]))[:2]
            print(pid, "US points near target:", [(p["attributes"]["customerPrice"], p["attributes"]["proceeds"]) for p in near])
        return

    results = {}
    for s in subs:
        pid = s["attributes"]["productId"]
        if pid not in TARGET: continue
        us_pts = get_all(f"/v1/subscriptions/{s['id']}/pricePoints", {"filter[territory]": "USA", "limit": 200})
        def us_point(price):
            return min(us_pts, key=lambda p: abs(float(p["attributes"]["customerPrice"]) - price))
        bands = {}
        for factor in (1.0, 0.60, 0.38):
            base = us_point(TARGET[pid] * factor)
            eq = get_all(f"/v1/subscriptionPricePoints/{base['id']}/equalizations", {"include": "territory", "limit": 200})
            bands[factor] = {"US": base["attributes"]["customerPrice"],
                             "points": {e["relationships"]["territory"]["data"]["id"]: e for e in eq}}
            bands[factor]["points"]["USA"] = base
        ok = fail = 0; errors = []
        territories = set(bands[1.0]["points"].keys())
        for t in sorted(territories):
            f = band(t)
            if f is None: continue
            pt = bands[f]["points"].get(t)
            if not pt: continue
            body = {"data": {"type": "subscriptionPrices",
                             "attributes": {"preserveCurrentPrice": False},
                             "relationships": {
                                 "subscription": {"data": {"type": "subscriptions", "id": s["id"]}},
                                 "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pt["id"]}},
                                 "territory": {"data": {"type": "territories", "id": t}}}}}
            r = call("POST", "/v1/subscriptionPrices", data=json.dumps(body))
            if r.status_code in (200, 201): ok += 1
            else:
                fail += 1
                if len(errors) < 4: errors.append((t, r.status_code, r.text[:300]))
        print(f"{pid}: bands US-equivalent {[bands[k]['US'] for k in (1.0, 0.60, 0.38)]}, set {ok}, failed {fail}")
        for e in errors: print("   ", e)
        results[pid] = {k: bands[k]["US"] for k in bands}
    # Free trial on yearly plans only: remove monthly intro offers.
    for s in subs:
        pid = s["attributes"]["productId"]
        if not pid.endswith(".monthly"): continue
        offers = get_all(f"/v1/subscriptions/{s['id']}/introductoryOffers", {"limit": 200})
        gone = sum(1 for o in offers if call("DELETE", f"/v1/subscriptionIntroductoryOffers/{o['id']}").status_code in (200, 204))
        print(f"{pid}: removed {gone} of {len(offers)} trial offers")
    # Spot check a few territories
    for s in subs:
        pid = s["attributes"]["productId"]
        if pid not in TARGET: continue
        prices = get_all(f"/v1/subscriptions/{s['id']}/prices", {"include": "subscriptionPricePoint,territory", "limit": 200})
        by_t = {}
        for p in prices:
            t = p["relationships"]["territory"]["data"]["id"]
            by_t.setdefault(t, []).append(p)
        inc = {i["id"]: i for i in []}
        print(pid, "price records:", len(prices))
    # Show customer prices for sample territories
    for s in subs:
        pid = s["attributes"]["productId"]
        if pid not in TARGET: continue
        r = call("GET", f"/v1/subscriptions/{s['id']}/prices", params={"include": "subscriptionPricePoint,territory", "limit": 200,
                 "filter[territory]": "USA,GBR,DEU,JPN,BRA,IDN,MEX,POL,ZAF,IND"})
        j = r.json()
        pts = {i["id"]: i for i in j.get("included", []) if i["type"] == "subscriptionPricePoints"}
        terr = {i["id"]: i for i in j.get("included", []) if i["type"] == "territories"}
        latest = {}
        for p in j.get("data", []):
            t = p["relationships"]["territory"]["data"]["id"]
            sd = p["attributes"].get("startDate") or ""
            if t not in latest or sd >= (latest[t]["attributes"].get("startDate") or ""):
                latest[t] = p
        row = []
        for t, p in sorted(latest.items()):
            pp = pts.get(p["relationships"]["subscriptionPricePoint"]["data"]["id"])
            cur = terr.get(t, {}).get("attributes", {}).get("currency", "")
            row.append(f"{t} {pp['attributes']['customerPrice'] if pp else '?'} {cur}")
        print(pid, " | ".join(row))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "inspect")
