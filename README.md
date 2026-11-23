# RainPulse — Live Rain Radar (v1)

An iPhone app with a home-screen widget: live rain radar animation, alerts before rain arrives,
hourly and 14-day forecasts, saved places worldwide, and Free / Essential / Pro subscriptions.
It's built with SwiftUI, MapKit, WidgetKit and StoreKit 2, has no third-party SDKs, and targets iOS 17 or later.

## What's in v1

| Feature | Free | Essential | Pro |
|---|---|---|---|
| Live radar map, worldwide | ✓ | ✓ | ✓ |
| Radar animation | −30 min → +30 min | −2 h → +2 h | −48 h → +2 h |
| "Rain in X min" summary | ✓ | ✓ | ✓ |
| Minute-by-minute (15-min) rain chart | 🔒 | ✓ | ✓ |
| Forecast | 24 h hourly, 2 days | 48 h hourly, 14 days | 48 h hourly, 14 days |
| Saved places | 3 | 20 | 20 |
| Rain alerts | Current location | Location + 20 places | Location + 20 places |
| Widgets | Small, Lock Screen | + Medium with 2-h rain chart | same |
| Clouds / Wind / Temperature layers | — | — | ✓ |

**Pricing (US base, same structure as RainViewer):**

| Product ID | Plan | Price | Trial |
|---|---|---|---|
| `rainpulse.essential.monthly` | Essential monthly | $4.99 | 14 days |
| `rainpulse.essential.yearly` | Essential yearly | $19.99 | 14 days |
| `rainpulse.pro.monthly` | Pro monthly | $7.99 | 14 days |
| `rainpulse.pro.yearly` | Pro yearly | $39.99 | 14 days |

Apple converts these prices for every country. In App Store Connect you can lower prices for
India and other price-sensitive markets (for example ₹149/month, ₹899/year for Essential). That usually lifts conversions.

## Data sources

| What | Source | Cost |
|---|---|---|
| Current, hourly, 10-day forecast, minute rain (US/UK/JP/AU/IE) | **Apple WeatherKit**: 500,000 calls/month included with the developer membership |
| 15-min rain where Apple has no minute data (e.g. India), days 11–14, fallback | Open-Meteo | Free while testing. **The free API is non-commercial**, so buy the API Standard plan before launch and set `OPEN_METEO_API_KEY` (the app switches to `customer-api.open-meteo.com` automatically). |
| Radar tiles (animated) | OpenWeather **Global Precipitation Maps – History & Forecast** (10-min steps, 2 days back, 2 h ahead worldwide) | Ask OpenWeather sales to enable it on your key |
| Radar tiles (fallback) | OpenWeather Weather Maps 1.0 `precipitation_new` | Free key, current frame only |
| Pro layers | OpenWeather Weather Maps 1.0 clouds / wind / temp | Free key |

If the animated product isn't enabled on your key, the app notices the 401/403 response and drops to
**live-only** mode by itself, so the map always shows something. To change provider later, edit
`RainPulse/Radar/RadarProvider.swift`. Tomorrow.io is already wired in as an option (its free plan is too small for production).

**Keeping tile costs down:** each animation step is one set of map tiles. Frames are capped at about 18 per animation,
tiles are cached on the device (256 MB), and zoom levels past 9 are upscaled from the cached tile instead of downloaded.

## Setup (one-time)

1. **Bundle ID and team.** Open `Config/Base.xcconfig` and set `BUNDLE_ID_BASE` (for example `com.neuralorbitx.rainpulse`)
   and `DEVELOPMENT_TEAM` (your 10-character Team ID from developer.apple.com → Membership).
2. **Identifiers.** On developer.apple.com → Identifiers:
   - Create the App Group `group.<BUNDLE_ID_BASE>`.
   - Create App IDs `<BUNDLE_ID_BASE>` and `<BUNDLE_ID_BASE>.widget`, both with **App Groups** turned on and linked to that group.
3. **API keys.** For local builds, copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill it in.
   For Xcode Cloud, add `OWM_API_KEY`, `OPEN_METEO_API_KEY` (and optionally `TOMORROW_API_KEY`) as **Secret** environment
   variables in the workflow. `ci_scripts/ci_post_clone.sh` writes them into the build.
4. **Privacy policy.** Host a short privacy page (GitHub Pages works) and put its URL in `PRIVACY_POLICY_URL`.
   Keep the `https:/$()/` trick: it stops Xcode reading `//` as the start of a comment.
5. **App Store Connect.**
   - Create the app with your bundle ID and name it **RainPulse: Live Rain Radar**.
   - Under Subscriptions, create one group called **RainPulse Premium** with the four product IDs above.
     Set Pro to level 1 and Essential to level 2, and add a 14-day free-trial introductory offer to each.
   - App Privacy: declare **Location (coarse) – App Functionality – not linked to identity – not used for tracking**.
     Coordinates are sent to the weather APIs to fetch forecasts.
6. **Build.** Push to GitHub, create an Xcode Cloud workflow (scheme **RainPulse**, Archive → TestFlight & App Store),
   and test on your iPhone through TestFlight. Subscriptions work in TestFlight sandbox, free of charge.

To add or remove files later, run `python3 tools/generate_project.py` to rebuild the Xcode project. Xcode isn't needed for this.

## Testing checklist (TestFlight)

- [ ] First launch: onboarding asks for location, then notifications
- [ ] Radar shows around you; play and slider animate (or "Live only" appears if your key lacks the animated product)
- [ ] Forecast tab: summary, 2-hour chart (locked on Free), hourly, daily
- [ ] Places: search "Tokyo", add it, bell toggle (Essential+), limit of 3 on Free
- [ ] Paywall: prices load, trial text shows, purchase in sandbox unlocks the chart, 2 h animation and 14 days
- [ ] Restore purchases works after reinstall
- [ ] Widget: add Small and Medium; Medium shows the chart only on Essential+
- [ ] Alerts: Settings → Rain alerts on; leave the phone overnight on a rainy day

## Known limits of v1 (upgrade path)

- **Alert timing is up to iOS.** Background App Refresh runs when iOS decides, often every 15–60 minutes,
  and less often in Low Power Mode. For guaranteed timing, add a small server that checks places and sends push notifications.
- **Radar quality depends on the provider.** OpenWeather mixes radar, satellite and models worldwide.
  Real radar from national weather services (a RainViewer-style setup) is the "upgrade later" step.
- **Not in v1:** ads, Apple Watch, Live Activities, hurricane tracker, 48-h archive at 10-min steps.

---

## App Store listing (copy-paste)

**Name (30):** RainPulse: Live Rain Radar
**Subtitle (30):** Rain alerts & weather map
**Keywords (100):** `weather,radar,rain,forecast,storm,alert,doppler,precipitation,map,monsoon,cyclone,nowcast,umbrella`
**Promotional text (170):** Know exactly when rain starts and stops. Live radar, a 2-hour rain forecast and alerts before it reaches you, anywhere in the world.

**Description:**

> RainPulse shows you where it's raining right now, and where the rain is heading next.
>
> LIVE RAIN RADAR
> • Animated radar map for anywhere in the world
> • Play back the last hours and see the forecast for the next 2 hours
> • Saved places pinned on the map
>
> KNOW BEFORE IT RAINS
> • "Rain in 25 min" at a glance
> • Rain alerts before showers reach you
> • Minute-by-minute rain chart for the next 2 hours
>
> FORECASTS YOU CAN PLAN WITH
> • Hourly forecast with chance of rain
> • 14-day forecast
> • °C/°F and mm/in follow your region automatically
>
> WIDGETS
> • Home Screen and Lock Screen widgets with the next-2-hours rain chart
>
> RAINPULSE ESSENTIAL & PRO
> Essential: 2-hour radar forecast, minute rain chart, 14-day forecast, alerts for up to 20 places, all widgets.
> Pro: everything in Essential plus 48-hour radar playback and clouds, wind and temperature layers.
> Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage them in Settings > Apple Account > Subscriptions.
>
> Terms: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy: (your privacy URL)
> Weather data by Open-Meteo.com and OpenWeather.

**Category:** Weather (secondary: Utilities) · **Age rating:** 4+
