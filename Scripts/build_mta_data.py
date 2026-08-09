#!/usr/bin/env python3
"""
build_mta_data.py — distill the MTA subway GTFS static feed into a compact bundle.

Downloads the official NYC subway GTFS zip and emits Resources/mta_subway.json
containing everything StepOff needs to plan a single-line "get off early" trip:

  - stations:  parent-station id -> {name, lat, lon}
  - routes:    route id -> {short_name, long_name, color}
  - patterns:  distinct ordered station sequences per (route, direction) with a
               trip count, so express/local variants are preserved
  - transfers: in-station / short-walk transfers (kept for a later phase)

Only the Python standard library is used (urllib, zipfile, csv, json), so this
runs anywhere without pip installs. Re-run to refresh when MTA updates the feed.

Usage:
    python3 Scripts/build_mta_data.py [--zip path/to/google_transit.zip]
"""

import argparse
import csv
import io
import json
import os
import sys
import urllib.request
import zipfile
from collections import Counter, defaultdict

GTFS_URL = "http://web.mta.info/developers/data/nyct/subway/google_transit.zip"

# Keep any distinct (route, direction) stop pattern serving at least this many
# trips. Filters out one-off/reroute patterns while keeping express+local+shuttle
# service variants.
MIN_PATTERN_TRIPS = 5

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.normpath(os.path.join(HERE, "..", "StepOff", "Resources", "mta_subway.json"))


def load_zip(zip_path):
    if zip_path:
        print(f"Reading GTFS from {zip_path}", file=sys.stderr)
        with open(zip_path, "rb") as f:
            return zipfile.ZipFile(io.BytesIO(f.read()))
    print(f"Downloading GTFS from {GTFS_URL} ...", file=sys.stderr)
    req = urllib.request.Request(GTFS_URL, headers={"User-Agent": "StepOff/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    print(f"  downloaded {len(data)/1_000_000:.1f} MB", file=sys.stderr)
    return zipfile.ZipFile(io.BytesIO(data))


def read_csv(zf, name):
    """Yield rows of a GTFS file as dicts (utf-8-sig to strip any BOM)."""
    with zf.open(name) as f:
        text = io.TextIOWrapper(f, encoding="utf-8-sig")
        yield from csv.DictReader(text)


def build(zf):
    # --- stops.txt: parent stations + platform -> parent map -------------------
    stations = {}            # parent_id -> {name, lat, lon}
    platform_to_parent = {}  # platform stop_id -> parent_id
    for row in read_csv(zf, "stops.txt"):
        sid = row["stop_id"]
        loc_type = row.get("location_type", "") or "0"
        parent = row.get("parent_station", "") or ""
        if loc_type == "1":  # a station (parent)
            stations[sid] = {
                "name": row["stop_name"],
                "lat": float(row["stop_lat"]),
                "lon": float(row["stop_lon"]),
            }
        if parent:
            platform_to_parent[sid] = parent
        else:
            # platform with no parent listed: it is its own station reference
            platform_to_parent[sid] = sid

    # Some feeds only list platform-level stops. Backfill any missing stations.
    for row in read_csv(zf, "stops.txt"):
        sid = row["stop_id"]
        parent = platform_to_parent.get(sid, sid)
        if parent not in stations:
            stations[parent] = {
                "name": row["stop_name"],
                "lat": float(row["stop_lat"]),
                "lon": float(row["stop_lon"]),
            }

    # --- routes.txt ------------------------------------------------------------
    routes = {}
    for row in read_csv(zf, "routes.txt"):
        rid = row["route_id"]
        routes[rid] = {
            "short_name": row.get("route_short_name") or rid,
            "long_name": row.get("route_long_name", ""),
            "color": (row.get("route_color") or "").strip(),
        }

    # --- trips.txt: trip_id -> (route, direction) ------------------------------
    trip_route = {}
    trip_dir = {}
    for row in read_csv(zf, "trips.txt"):
        tid = row["trip_id"]
        trip_route[tid] = row["route_id"]
        trip_dir[tid] = int(row.get("direction_id") or 0)

    # --- stop_times.txt: assemble ordered parent-station sequence per trip ------
    # This is the big file; stream it once, grouping by trip_id.
    print("Parsing stop_times.txt (large) ...", file=sys.stderr)
    trip_stops = defaultdict(list)  # trip_id -> [(seq, parent_station), ...]
    for row in read_csv(zf, "stop_times.txt"):
        tid = row["trip_id"]
        if tid not in trip_route:
            continue
        parent = platform_to_parent.get(row["stop_id"], row["stop_id"])
        trip_stops[tid].append((int(row["stop_sequence"]), parent))

    # Collapse each trip to an ordered, de-duplicated station list, then count
    # distinct sequences per (route, direction).
    pattern_counts = Counter()  # (route, dir, tuple(stations)) -> trip count
    for tid, seq in trip_stops.items():
        seq.sort(key=lambda x: x[0])
        ordered = []
        for _, parent in seq:
            if not ordered or ordered[-1] != parent:
                ordered.append(parent)
        if len(ordered) < 2:
            continue
        key = (trip_route[tid], trip_dir[tid], tuple(ordered))
        pattern_counts[key] += 1

    patterns = []
    for (route, direction, stops), count in pattern_counts.items():
        if count < MIN_PATTERN_TRIPS:
            continue
        patterns.append({
            "route": route,
            "direction": direction,
            "stations": list(stops),
            "count": count,
        })
    patterns.sort(key=lambda p: (p["route"], p["direction"], -p["count"]))

    # --- transfers.txt (optional; kept for phase 2) ----------------------------
    transfers = []
    if "transfers.txt" in zf.namelist():
        for row in read_csv(zf, "transfers.txt"):
            frm = platform_to_parent.get(row["from_stop_id"], row["from_stop_id"])
            to = platform_to_parent.get(row["to_stop_id"], row["to_stop_id"])
            if frm == to:
                continue
            transfers.append({
                "from": frm,
                "to": to,
                "min_time": int(row.get("min_transfer_time") or 0),
            })

    # Keep only stations actually referenced by a kept pattern (+ transfer ends).
    used = set()
    for p in patterns:
        used.update(p["stations"])
    for t in transfers:
        used.add(t["from"])
        used.add(t["to"])
    stations = {sid: s for sid, s in stations.items() if sid in used}
    transfers = [t for t in transfers if t["from"] in stations and t["to"] in stations]

    return {
        "source": GTFS_URL,
        "stations": stations,
        "routes": routes,
        "patterns": patterns,
        "transfers": transfers,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", help="use a local google_transit.zip instead of downloading")
    args = ap.parse_args()

    zf = load_zip(args.zip)
    data = build(zf)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w") as f:
        json.dump(data, f, separators=(",", ":"))

    size_kb = os.path.getsize(OUT_PATH) / 1024
    print(
        f"Wrote {OUT_PATH}\n"
        f"  stations={len(data['stations'])} routes={len(data['routes'])} "
        f"patterns={len(data['patterns'])} transfers={len(data['transfers'])} "
        f"size={size_kb:.0f} KB",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
