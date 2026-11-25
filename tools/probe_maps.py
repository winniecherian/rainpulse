"""Probe map tile sources (read-only): NASA GIBS satellite layers, CARTO and Stadia basemaps."""
import re, sys, urllib.request, xml.etree.ElementTree as ET
UA = {"User-Agent": "RainPulse-probe/1.0"}
def get(url, n=None):
    req = urllib.request.Request(url, headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.headers.get("Content-Type"), r.read(n) if n else r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type"), b""
    except Exception as e:
        return str(e), None, b""

code, ct, xml = get("https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml")
print("GIBS caps", code, len(xml))
ns = {"w": "http://www.opengis.net/wmts/1.0", "ows": "http://www.opengis.net/ows/1.1"}
root = ET.fromstring(xml)
pat = re.compile(sys.argv[2] if len(sys.argv) > 2 else r"Himawari|GOES|Geostationary|VIIRS_(SNPP|NOAA20|NOAA21)_CorrectedReflectance_TrueColor|BlueMarble|MODIS_Terra_CorrectedReflectance_TrueColor|IR_Clouds|Cloud")
found = []
for layer in root.iter("{http://www.opengis.net/wmts/1.0}Layer"):
    ident = layer.find("ows:Identifier", ns).text
    if not pat.search(ident): continue
    fmt = [f.text for f in layer.findall("w:Format", ns)]
    tms = [t.find("w:TileMatrixSet", ns).text for t in layer.findall("w:TileMatrixSetLink", ns)]
    dim = layer.find("w:Dimension", ns)
    default = dim.find("w:Default", ns).text if dim is not None else None
    values = [v.text for v in dim.findall("w:Value", ns)][-1:] if dim is not None else []
    res = [r.get("template") for r in layer.findall("w:ResourceURL", ns)][:1]
    found.append(ident)
    print(f"{ident} | {fmt} | {tms} | default={default} | last={values} | {res}")
print("matched", len(found))
for ident in [i for i in found if re.search(r"Himawari|GOES|Geostationary", i)][:6]:
    for z, y, x in [(3, 3, 6), (2, 1, 2)]:
        c, t, b = get(f"https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/{ident}/default/default/GoogleMapsCompatible_Level6/{z}/{y}/{x}.png", 4096)
        print("tile", ident, z, y, x, c, t, len(b))
for url in ["https://a.basemaps.cartocdn.com/dark_all/5/23/14@2x.png",
            "https://a.basemaps.cartocdn.com/rastertiles/dark_nolabels/5/23/14@2x.png",
            "https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/5/23/14@2x.png",
            "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/VIIRS_SNPP_CorrectedReflectance_TrueColor/default/default/GoogleMapsCompatible_Level9/3/3/5.jpg",
            "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/BlueMarble_NextGeneration/default/GoogleMapsCompatible_Level8/3/3/5.jpeg"]:
    c, t, b = get(url, 4096)
    print("probe", url, c, t, len(b))
