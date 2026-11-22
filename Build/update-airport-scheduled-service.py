#!/usr/bin/env python3
"""Backfill the globe's scheduled-service flag from the OurAirports CSV."""

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("airports_csv", type=Path)
    parser.add_argument("snapshot_date")
    args = parser.parse_args()
    catalog_path = Path(__file__).resolve().parents[1] / "App/Resources/airport-data.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    indexes = {key: defaultdict(list) for key in ("icao_code", "ident", "iata_code")}
    with args.airports_csv.open(encoding="utf-8-sig", newline="") as file:
        for airport in csv.DictReader(file):
            for key, index in indexes.items():
                if airport[key]:
                    index[airport["iso_country"], airport[key]].append(airport)

    counts = {True: 0, False: 0}
    for airport in catalog["airports"]:
        airport.pop("scheduledService", None)
        country = airport.get("countryCode")
        for raw_key, catalog_key in (("icao_code", "icao"), ("ident", "id"), ("iata_code", "iata")):
            matches = indexes[raw_key].get((country, airport.get(catalog_key)), ())
            if len(matches) != 1 or matches[0]["type"] != airport.get("type"):
                continue
            flag = matches[0]["scheduled_service"]
            if flag in ("yes", "no"):
                airport["scheduledService"] = flag == "yes"
                counts[flag == "yes"] += 1
                break

    provider = next(source for source in catalog["sources"] if source["url"] == "https://ourairports.com/data/")
    provider["detail"] = (
        "公有领域。目录保留有定期航班记录的机场，并补充列为大型的民用机场。"
        "中国民航局的运输机场和通用机场公开名录用于补充境内机场。"
        f"地球的定期航班分类采用 {args.snapshot_date} 快照中的 scheduled_service；"
        "分类、坐标和跑道数据可能存在滞后。"
    )
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Scheduled {counts[True]}, other {counts[False]}, unknown {len(catalog['airports']) - sum(counts.values())}")


if __name__ == "__main__":
    main()
