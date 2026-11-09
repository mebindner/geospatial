"""Download ECA&D frost-day index (FD) for Danish stations and a Natural Earth outline.

Writes data/processed/stations.json:
{staid: {name, lat, lon, fd: {year: days}, fdm: {year: [Jan..Dec days or None]}}}
"""
import io, json, re, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW, PROC = ROOT / "data/raw", ROOT / "data/processed"
FD_URL = "https://knmi-ecad-assets-prd.s3.amazonaws.com/download/millennium/data/ECA_indexFD.zip"
NE_URL = "https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-10m.json"


def get(url, dest):
    if not dest.exists():
        print("downloading", url)
        urllib.request.urlretrieve(url, dest)
    return dest


def dms(s):
    sign = -1 if s[0] == "-" else 1
    d, m, sec = (float(x) for x in s[1:].split(":"))
    return sign * (d + m / 60 + sec / 3600)


def main():
    RAW.mkdir(parents=True, exist_ok=True); PROC.mkdir(parents=True, exist_ok=True)
    zf = zipfile.ZipFile(get(FD_URL, RAW / "ECA_indexFD.zip"))
    get(NE_URL, RAW / "countries-10m.json")
    meta = zf.read("stations_FD.txt").decode("latin-1").splitlines()
    ids = [int(l.split(",")[0]) for l in meta if ",DENMARK" in l]
    out = {}
    for sid in ids:
        name = lat = lon = None; fd = {}; fdm = {}
        for l in zf.read(f"indexFD_{sid:06d}.txt").decode("latin-1").splitlines():
            m = re.search(r"DENMARK\s+(.+?)\s+\(STAID", l)
            if m: name = m.group(1).strip()
            if l.startswith("LATITUDE"): lat = dms(l.split()[-1])
            if l.startswith("LONGITUDE"): lon = dms(l.split()[-1])
            t = l.split()
            if len(t) >= 3 and t[0].isdigit() and len(t[1]) == 4 and t[1].isdigit():
                v = int(t[2])  # annual value, unit 0.01 days
                if v != -999999: fd[int(t[1])] = round(v / 100)
                if len(t) >= 21:  # columns 10-21: January..December
                    fdm[int(t[1])] = [None if int(x) == -999999 else round(int(x) / 100) for x in t[9:21]]
        out[sid] = dict(name=name, lat=lat, lon=lon, fd=fd, fdm=fdm)
    (PROC / "stations.json").write_text(json.dumps(out))
    print(len(out), "Danish stations ->", PROC / "stations.json")


if __name__ == "__main__":
    main()
