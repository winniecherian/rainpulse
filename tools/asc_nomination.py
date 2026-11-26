"""Create a DRAFT App Store featuring nomination (not submitted) for RainPulse's launch."""
import json, sys
sys.path.insert(0, "tools")
from asc_pricing import call, get_all, BUNDLE

app = get_all("/v1/apps", {"filter[bundleId]": BUNDLE})[0]
existing = call("GET", "/v1/nominations", params={"filter[relatedApps]": app["id"], "filter[state]": "DRAFT,SUBMITTED"})
print("list:", existing.status_code, existing.text[:300])
body = {"data": {"type": "nominations", "attributes": {
    "name": "RainPulse launch: the Rain Clock",
    "type": "APP_LAUNCH",
    "description": ("RainPulse answers the one weather question people ask most: when will it rain? Its signature Rain Clock "
                    "turns the next two hours into a dial, minute by minute, so anyone can read rain start, intensity and stop "
                    "at a glance. Built natively in SwiftUI with WeatherKit, WidgetKit and on-device Apple Intelligence "
                    "(Foundation Models) for private AI insights. Global from day one: live radar, a free 48-hour rain forecast "
                    "animation, a cyclone tracker with storm cones and alerts, animated wind flow and air quality, localized in "
                    "14 App Store languages including Hindi, Tamil, Arabic, Japanese and Vietnamese. Private by design: no account, "
                    "no ads, no tracking, optional Face ID lock. Timely for Bay of Bengal cyclone season and the Southern "
                    "Hemisphere summer storm season."),
    "submitted": False,
    "publishStartDate": "2026-12-22T00:00:00Z",
    "deviceFamilies": ["IPHONE"],
    "locales": ["en-US", "en-GB", "en-AU", "es-ES", "es-MX", "pt-BR", "de-DE", "fr-FR", "hi", "id", "ja", "ar-SA", "ta-IN", "vi"],
    "hasInAppEvents": False,
    "launchInSelectMarketsFirst": False,
    "preOrderEnabled": False,
    "notes": "Indie developer NeuralOrbitX (Chennai, India). Uses Apple Intelligence on-device for AI insights.",
    "supplementalMaterialsUris": ["https://rainpulse-app.web.app/"]},
    "relationships": {"relatedApps": {"data": [{"type": "apps", "id": app["id"]}]}}}}
r = call("POST", "/v1/nominations", data=json.dumps(body))
print("create:", r.status_code, r.text[:600])
