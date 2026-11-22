#!/usr/bin/env python3
"""Generate the location-free airport and passenger-route catalogs for MainlandReview."""

import argparse
import json
import re
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[1] / "App" / "Resources"
DIRECTORY_FIELDS = (
    "id", "iata", "icao", "name", "city", "country", "countryCode", "type",
    "localizedName", "localizedCity", "localizedNameAliases", "localizedNameSource",
    "civilUse", "operatingStatus", "opened",
)
STAT_FIELDS = ("sourceID", "period", "flights", "passengers", "operators", "verifiedNonstop")
DIRECTORY_SOURCES = {
    "https://ourairports.com/data/",
    "https://www.caac.gov.cn/GYMH/MHGK/MYJC/",
    "https://www.wikidata.org/wiki/Wikidata:Licensing",
    "https://download.geonames.org/export/dump/",
}
MILITARY_NAME = re.compile(
    r"军事基地|軍事基地|空军基地|空軍基地|军用机场|軍用機場|"
    r"\b(?:air force base|military base|army air[fp]\w+|naval air station)\b",
    re.I,
)
CHINA_REGION_LABELS = {"HK": "中国香港", "MO": "中国澳门", "TW": "中国台湾"}


def read(name):
    return json.loads((RESOURCES / name).read_text(encoding="utf-8"))


def project(row, fields):
    return {key: row[key] for key in fields if key in row}


def is_public_airport(airport, evidence):
    if not airport["iata"] or airport["type"] not in ("large_airport", "medium_airport", "small_airport"):
        return False
    names = " ".join(airport.get(key) or "" for key in ("name", "localizedName"))
    if MILITARY_NAME.search(names):
        return False
    if airport.get("countryCode") == "CN":
        return airport.get("civilUse") == "运输机场"
    return airport["id"] in evidence


def build():
    catalog = read("airport-data.json")
    observed = read("observed-routes.json")
    public_pairs = catalog["routes"] + observed["routes"]
    evidence = {row[key] for row in public_pairs for key in ("origin", "destination")}
    airports = []
    for airport in catalog["airports"]:
        if not is_public_airport(airport, evidence):
            continue
        record = project(airport, DIRECTORY_FIELDS)
        region = CHINA_REGION_LABELS.get(record.get("countryCode"))
        if region:
            record["country"] = region
        airports.append(record)
    ids = {row["id"] for row in airports}

    def directory_route(row):
        return row["origin"] in ids and row["destination"] in ids

    routes = [row for row in catalog["routes"] if directory_route(row)]
    sources = [
        dict(source, title="OurAirports · 开放机场目录", detail="公有领域。此版仅使用机场名称、代号和城市等目录字段。")
        if source["url"] == "https://ourairports.com/data/" else source
        for source in catalog["sources"] if source["url"] in DIRECTORY_SOURCES
    ]
    observed_routes = []
    for row in observed["routes"]:
        if directory_route(row):
            trimmed = project(row, ("origin", "destination", "distanceKm"))
            trimmed["observations"] = [project(entry, STAT_FIELDS) for entry in row["observations"]]
            observed_routes.append(trimmed)
    source_ids = {entry["sourceID"] for row in observed_routes for entry in row["observations"]}
    source_ids.add("airportmiles")
    endpoint_count = len({row[key] for row in observed_routes for key in ("origin", "destination")})
    assert {"HKG", "SIN", "SFO", "PEK", "PKX"}.issubset(ids), "Missing expected public airport"
    assert routes and observed_routes, "No passenger routes survived the directory filter"
    return {
        "airport-data-mainland.json": {
            "airports": airports, "routes": routes, "sources": sources,
            "updatedAt": catalog["updatedAt"], "routeDistanceMethod": catalog["routeDistanceMethod"],
            "routeCoverage": catalog["routeCoverage"],
        },
        "observed-routes-mainland.json": {
            "asOf": observed["asOf"],
            "coverage": (
                f"{len(observed_routes):,} 条历史客运机场对，涉及 {endpoint_count:,} 座目录机场。"
                "按各来源统计期展示，合并已报告方向。距离为两机场间大圆距离。"
                "部分记录可能有经停，最长不经停比较只使用已核实的记录。"
            ),
            "sources": [source for source in observed["sources"] if source["id"] in source_ids],
            "routes": observed_routes,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify committed catalogs instead of rewriting them")
    args = parser.parse_args()
    for name, body in build().items():
        target = RESOURCES / name
        content = json.dumps(body, ensure_ascii=False, separators=(",", ":")) + "\n"
        if args.check:
            if target.read_text(encoding="utf-8") != content:
                parser.error(f"{name} is stale. Run python3 Build/prepare-mainland-catalog.py.")
        else:
            target.write_text(content, encoding="utf-8")
        print(f"{name}: {len(body.get('airports', [])):,} airport rows, {len(body['routes']):,} route rows")


if __name__ == "__main__":
    main()
