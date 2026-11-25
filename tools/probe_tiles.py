"""Download a few sample map tiles and print them base64-encoded (read-only probe)."""
import base64, urllib.request
G = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"
tiles = {
  "him_ir": f"{G}/Himawari_AHI_Band13_Clean_Infrared/default/default/GoogleMapsCompatible_Level6/3/3/5.png",
  "him_vis": f"{G}/Himawari_AHI_Band3_Red_Visible_1km/default/default/GoogleMapsCompatible_Level7/3/3/5.png",
  "goes_ir": f"{G}/GOES-East_ABI_Band13_Clean_Infrared/default/default/GoogleMapsCompatible_Level6/2/1/1.png",
  "goes_geo": f"{G}/GOES-East_ABI_GeoColor/default/default/GoogleMapsCompatible_Level7/2/1/1.png",
  "marble": f"{G}/BlueMarble_ShadedRelief_Bathymetry/default/GoogleMapsCompatible_Level8/3/3/5.jpeg",
  "viirs": f"{G}/VIIRS_NOAA20_CorrectedReflectance_TrueColor/default/default/GoogleMapsCompatible_Level9/3/3/5.jpg",
  "carto": "https://a.basemaps.cartocdn.com/dark_all/3/5/3@2x.png",
}
for name, url in tiles.items():
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "RainPulse-probe"}), timeout=60) as r:
            data = r.read()
        print(f"TILE {name} {len(data)} " + base64.b64encode(data).decode())
    except Exception as e:
        print(f"TILE {name} ERR {e}")
