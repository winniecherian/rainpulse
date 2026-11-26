"""Print the structure of official alert feeds (SACHET India, IMD CAP, Open-Meteo multi-model)."""
import re, sys, requests
H = {"User-Agent": "RainPulse/1.0 (probe)"}
def show(url, n=3000):
    try:
        r = requests.get(url, headers=H, timeout=30)
        print(f"\n===== {url}  HTTP {r.status_code}  {len(r.content)} bytes  {r.headers.get('content-type')}")
        print(r.text[:n]); return r.text
    except Exception as e:
        print(f"\n===== {url} ERROR {e}"); return ""
rss = show("https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml", 4000)
links = re.findall(r"<link>([^<]+)</link>", rss)[1:4]
for l in links: show(l.strip(), 5000)
tn = show("https://sachet.ndma.gov.in/cap_public_website/rss/rss_tamilnadu.xml", 1500)
imd = show("https://cap-sources.s3.amazonaws.com/in-imd-en/rss.xml", 2500)
il = re.findall(r"<link>([^<]+\.xml)</link>", imd)[:1]
for l in il: show(l.strip(), 4000)
show("https://api.open-meteo.com/v1/forecast?latitude=13.08&longitude=80.27&hourly=precipitation,precipitation_probability&models=ecmwf_ifs025,gfs_seamless,icon_seamless,gem_seamless&forecast_days=2&timezone=auto", 1500)
show("https://ensemble-api.open-meteo.com/v1/ensemble?latitude=13.08&longitude=80.27&hourly=precipitation&models=ecmwf_ifs025&forecast_days=1", 800)
