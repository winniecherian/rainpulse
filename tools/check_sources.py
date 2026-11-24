"""Live check of every external data source RainPulse uses. Exit 1 if any is broken."""
import os, sys, io, math, datetime as dt, requests
from PIL import Image

OK, FAIL = [], []


def check(name, fn):
    try:
        msg = fn()
        OK.append(name)
        print(f"PASS  {name}: {msg}")
    except Exception as e:
        FAIL.append(name)
        print(f"FAIL  {name}: {e}")


def get(url, **kw):
    r = requests.get(url, timeout=45, headers={"User-Agent": "RainPulse-check"}, **kw)
    r.raise_for_status()
    return r


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def open_meteo():
    cur = ("temperature_2m,weather_code,precipitation,apparent_temperature,relative_humidity_2m,uv_index,"
           "wind_speed_10m,wind_gusts_10m,wind_direction_10m,pressure_msl,visibility,dew_point_2m")
    j = get("https://api.open-meteo.com/v1/forecast", params={
        "latitude": "13.08", "longitude": "80.27", "current": cur, "minutely_15": "precipitation",
        "hourly": "temperature_2m,precipitation_probability,precipitation,weather_code",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max",
        "forecast_days": 14, "timezone": "auto"}).json()
    missing = [k for k in cur.split(",") if k not in j["current"]]
    assert not missing, f"missing current fields {missing}"
    assert len(j["daily"]["time"]) == 14 and len(j["minutely_15"]["precipitation"]) > 8
    return f"{j['current']['temperature_2m']} C, code {j['current']['weather_code']}, tz {j.get('timezone')}"


def air():
    j = get("https://air-quality-api.open-meteo.com/v1/air-quality",
            params={"latitude": "13.08", "longitude": "80.27", "current": "us_aqi,pm2_5,pm10"}).json()
    assert j["current"]["us_aqi"] is not None
    return f"AQI {j['current']['us_aqi']}"


def erddap(var):
    t = dt.datetime.utcnow().replace(minute=0, second=0, microsecond=0)
    t = t.replace(hour=(t.hour // 3) * 3)
    q = f"{var}%5B({iso(t)})%5D%5B(10):2:(16)%5D%5B(76):2:(84)%5D"
    j = get(f"https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ncep_global.json?{q}").json()
    rows = j["table"]["rows"]
    assert len(rows) >= 9, "too few rows"
    return f"{len(rows)} grid points at {iso(t)}"


def rain_window():
    t0 = dt.datetime.utcnow().replace(minute=0, second=0, microsecond=0)
    t1 = t0 + dt.timedelta(hours=48)
    j = get("https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ncep_global.json?"
            f"pratesfc%5B({iso(t0)}):1:({iso(t1)})%5D%5B(0)%5D%5B(0)%5D").json()
    n = len(j["table"]["rows"])
    assert n >= 8, f"only {n} future steps"
    return f"{n} forecast steps over 48 h"


def gdacs():
    frm = (dt.date.today() - dt.timedelta(days=10)).isoformat()
    to = (dt.date.today() + dt.timedelta(days=1)).isoformat()
    r = get(f"https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?eventlist=TC"
            f"&fromdate={frm}&todate={to}&alertlevel=green;orange;red")
    j = r.json() if r.text.strip() else {"features": []}
    feats = j.get("features", [])
    for f in feats[:1]:
        p = f["properties"]
        assert "eventid" in p and "geometry" in p.get("url", {}), "event format changed"
        assert "features" in get(p["url"]["geometry"]).json()
    return f"{len(feats)} storms in last 10 days"


def owm():
    key = os.environ.get("OWM_API_KEY", "")
    assert key, "OWM_API_KEY not set"
    z, lat, lon = 4, 13.08, 80.27
    n = 2 ** z
    x = int((lon + 180) / 360 * n)
    r = math.radians(lat)
    y = int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
    done = []
    for layer in ["precipitation_new", "clouds_new", "wind_new", "temp_new", "pressure_new"]:
        im = Image.open(io.BytesIO(get(f"https://tile.openweathermap.org/map/{layer}/{z}/{x}/{y}.png?appid={key}").content))
        assert im.size == (256, 256)
        done.append(layer.split("_")[0])
    return "tiles OK: " + ", ".join(done)


check("Open-Meteo forecast", open_meteo)
check("Open-Meteo air quality", air)
check("NOAA GFS wind (PacIOOS)", lambda: erddap("ugrd10m"))
check("NOAA GFS rain (PacIOOS)", lambda: erddap("pratesfc"))
check("NOAA GFS 48 h rain window", rain_window)
check("GDACS cyclones", gdacs)
check("OpenWeather map tiles", owm)
print(f"\n{len(OK)} passed, {len(FAIL)} failed")
sys.exit(1 if FAIL else 0)
