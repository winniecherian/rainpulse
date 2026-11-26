"""Print SACHET CAP polygon file format and Tamil Nadu alerts."""
import re, requests
H = {"User-Agent": "RainPulse/1.0 (probe)"}
g = lambda u: requests.get(u, headers=H, timeout=30)
rss = g("https://sachet.ndma.gov.in/cap_public_website/rss/rss_india.xml").text
items = re.findall(r"<item>(.*?)</item>", rss, re.S)
print("items", len(items)); print("pubDates", re.findall(r"<pubDate>([^<]+)", rss)[1], "...", re.findall(r"<pubDate>([^<]+)", rss)[-1])
print("authors", sorted(set(re.findall(r"<author>[^(]*\(([^)]+)\)", rss))))
print("categories", sorted(set(re.findall(r"<category>([^<]+)", rss))))
shown = 0
for it in items:
    if "Chennai" not in it and "Tamil" not in it: continue
    link = re.search(r"<link>([^<]+)", it).group(1)
    cap = g(link).text
    print("\n---", link, len(cap)); print("\n".join(l for l in cap.splitlines() if re.search(r"areaDesc|event>|severity|expires|msgType|sender>|headline|Polygon|polygon|circle", l))[:1500])
    pu = re.search(r"(https://[^<]+FetchPolygonXMLFile[^<]+)", cap)
    if pu and shown < 2:
        p = g(pu.group(1).replace("&amp;", "&"))
        print("POLYGON", p.status_code, len(p.content), p.headers.get("content-type")); print(p.text[:1200]); print("...", p.text[-300:])
    shown += 1
    if shown >= 4: break
