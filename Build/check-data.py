#!/usr/bin/env python3
import json
import math
import re
from calendar import monthrange
from collections import Counter
from datetime import date
from pathlib import Path
from urllib.parse import urlparse


def distance_km(origin, destination):
    origin_lat = math.radians(origin["lat"])
    destination_lat = math.radians(destination["lat"])
    latitude_delta = destination_lat - origin_lat
    longitude_delta = math.radians(destination["lon"] - origin["lon"])
    a = (math.sin(latitude_delta / 2) ** 2
         + math.cos(origin_lat) * math.cos(destination_lat) * math.sin(longitude_delta / 2) ** 2)
    return 2 * 6371.0088 * math.asin(min(1, math.sqrt(a)))


def check_catalog(path):
    with path.open(encoding="utf-8") as source:
        catalog = json.load(source)
    airports = {airport["id"]: airport for airport in catalog["airports"]}
    assert len(airports) == len(catalog["airports"]), "Duplicate airport identifier"
    for identity, airport in airports.items():
        assert -90 <= airport["lat"] <= 90, f"Invalid airport latitude for {identity}"
        assert -180 <= airport["lon"] <= 180, f"Invalid airport longitude for {identity}"
        assert re.search(r"[\u3400-\u9fff]", airport.get("localizedName") or ""), f"Missing Chinese airport name for {identity}"

    for route in catalog["routes"]:
        origin, destination = route["origin"], route["destination"]
        assert origin != destination, f"Airport loop found for {origin}"
        assert origin in airports and destination in airports, f"Unknown route endpoint for {origin}–{destination}"
        assert abs(distance_km(airports[origin], airports[destination]) - route["distanceKm"]) <= 2, (
            f"Incorrect airport-to-airport distance for {origin}–{destination}"
        )
        source_url = urlparse(route["sourceURL"])
        assert source_url.scheme == "https" and source_url.hostname, f"Missing source URL for {origin}–{destination}"
        if route.get("validFrom") and route.get("validThrough"):
            assert date.fromisoformat(route["validFrom"]) <= date.fromisoformat(route["validThrough"]), (
                f"Reversed timetable period for {origin}–{destination}"
            )

    assert airports["HKG"]["terminals"], "Hong Kong model has no terminal metadata"
    assert airports["HKG"]["runways"], "Hong Kong model has no runway metadata"
    assert any(
        (route["origin"], route["destination"], route.get("flightNumber"), route.get("aircraftID"))
        == ("HKG", "SIN", "SQ875", "a350-900")
        for route in catalog["routes"]
    ), "Missing cross-linked HKG–SIN A350-900 service"
    print(f"Checked {len(airports):,} airports and {len(catalog['routes']):,} routes")
    reference_names = sum(airport.get("localizedNameSource") == "参考译名" for airport in airports.values())
    print(f"Checked {len(airports):,} Chinese airport names, including {reference_names:,} reference translations")
    check_model_coverage(path.parent, airports)
    check_observed_routes(path.parent / "observed-routes.json", airports)


def nonempty_text(value):
    return isinstance(value, str) and bool(value.strip())


def https_url(value):
    if not nonempty_text(value):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.hostname)


def observed_period_bounds(period):
    def date_bounds(value):
        if re.fullmatch(r"\d{4}", value):
            year = int(value)
            return date(year, 1, 1), date(year, 12, 31)
        if re.fullmatch(r"\d{4}-\d{2}", value):
            year, month = map(int, value.split("-"))
            return date(year, month, 1), date(year, month, monthrange(year, month)[1])
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValueError(f"Invalid statistical date {value!r}")
        day = date.fromisoformat(value)
        return day, day

    parts = period.split("…")
    if len(parts) == 1:
        return date_bounds(parts[0])
    if len(parts) == 2:
        return date_bounds(parts[0])[0], date_bounds(parts[1])[1]
    raise ValueError(f"Invalid statistical period {period!r}")


def check_observed_routes(path, airports):
    with path.open(encoding="utf-8") as source:
        catalog = json.load(source)
    assert isinstance(catalog, dict), "Observed route catalog must be an object"
    snapshot = catalog.get("asOf")
    assert nonempty_text(snapshot) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", snapshot), "Missing ISO snapshot date"
    snapshot_date = date.fromisoformat(snapshot)
    assert nonempty_text(catalog.get("coverage")), "Missing observed route coverage description"
    assert isinstance(catalog.get("sources"), list) and catalog["sources"], "Missing observed route sources"
    assert isinstance(catalog.get("routes"), list) and catalog["routes"], "Missing observed route records"

    sources = {}
    for source in catalog["sources"]:
        assert isinstance(source, dict), "Invalid observed route source record"
        identity = source.get("id")
        assert nonempty_text(identity) and identity not in sources, f"Invalid or duplicate route source {identity!r}"
        assert nonempty_text(source.get("title")) and https_url(source.get("url")), f"Incomplete route source {identity}"
        assert source.get("detail") is None or nonempty_text(source["detail"]), f"Empty attribution detail for {identity}"
        sources[identity] = source

    pairs = {}
    endpoints = set()
    source_observations = Counter()
    source_verified = Counter()
    verified_pairs = {}
    latest_observed = None
    max_distance_error = 0
    for route in catalog["routes"]:
        assert isinstance(route, dict), "Invalid observed route record"
        a, b = route.get("origin"), route.get("destination")
        label = f"{a}–{b}"
        assert nonempty_text(a) and nonempty_text(b) and a in airports and b in airports, f"Unknown endpoint for {label}"
        assert a < b, f"Observed pair must use distinct alphabetical endpoints for {label}"
        assert (a, b) not in pairs, f"Duplicate observed pair {label}"
        endpoints.update((a, b))
        pairs[a, b] = route
        distance = route.get("distanceKm")
        assert type(distance) in (int, float) and math.isfinite(distance) and distance > 0, f"Invalid distance for {label}"
        error = abs(distance_km(airports[a], airports[b]) - distance)
        assert error <= 1, f"Incorrect distance for {label} ({distance} km, error {error:.2f} km)"
        max_distance_error = max(max_distance_error, error)
        observations = route.get("observations")
        assert isinstance(observations, list) and observations, f"Missing statistics for {label}"
        seen = set()
        for observation in observations:
            assert isinstance(observation, dict), f"Invalid observation for {label}"
            identity = observation.get("sourceID")
            period = observation.get("period")
            assert nonempty_text(identity) and identity in sources, f"Unknown source {identity!r} for {label}"
            assert nonempty_text(period), f"Missing period in {label} from {identity}"
            assert (identity, period) not in seen, f"Duplicate observation in {label} from {identity} for {period}"
            seen.add((identity, period))
            try:
                start, end = observed_period_bounds(period)
            except ValueError as error:
                raise AssertionError(f"Invalid period in {label} from {identity}: {error}") from error
            assert start <= end <= snapshot_date, f"Invalid date range in {label} from {identity}: {period}"

            measures = [observation[field] for field in ("flights", "passengers") if observation.get(field) is not None]
            assert measures and all(type(value) is int and value > 0 for value in measures), (
                f"Missing or nonpositive counts in {label} from {identity} for {period}"
            )
            operators = observation.get("operators")
            if operators is not None:
                assert isinstance(operators, list), f"Invalid operator list in {label} from {identity}"
                names = set()
                for operator in operators:
                    assert isinstance(operator, dict), f"Invalid operator in {label} from {identity}"
                    airline, aircraft = operator.get("airline"), operator.get("aircraft")
                    assert nonempty_text(airline) and airline not in names, f"Invalid or duplicate airline in {label}"
                    names.add(airline)
                    assert isinstance(aircraft, list) and all(nonempty_text(model) for model in aircraft), (
                        f"Invalid aircraft list in {label} for {airline}"
                    )
                    assert len(set(aircraft)) == len(aircraft), f"Duplicate aircraft in {label} for {airline}"
            verified = observation.get("verifiedNonstop")
            assert verified is None or type(verified) is bool, f"Invalid direct verification flag in {label}"
            verification_url = observation.get("verificationURL")
            assert verification_url is None or (verified is True and https_url(verification_url)), (
                f"Invalid verification URL in {label} from {identity}"
            )
            assert observation.get("note") is None or nonempty_text(observation["note"]), f"Empty observation note in {label}"
            source_observations[identity] += 1
            if verified:
                source_verified[identity] += 1
                verified_pairs.setdefault((a, b), []).append(observation)
            latest_observed = end if latest_observed is None else max(latest_observed, end)

    assert {"hkg", "bts", "eurostat"} <= source_observations.keys(), "Missing expected primary route sources"
    assert sources.keys() - source_observations.keys() <= {"airportmiles"}, "Unused source in observed route catalog"
    hkg_dfw = next((item for item in verified_pairs.get(("DFW", "HKG"), []) if item["sourceID"] == "hkg"), None)
    sin_jfk = next((item for item in verified_pairs.get(("JFK", "SIN"), []) if item["sourceID"] == "bts"
                    and any("Airbus A350-900" in operator["aircraft"] for operator in item.get("operators", []))), None)
    assert hkg_dfw and hkg_dfw.get("flights"), "Missing verified HKG–DFW airport-board operations"
    assert sin_jfk and sin_jfk.get("flights"), "Missing verified SIN–JFK A350-900 operations"
    countries = {airports[code].get("countryCode") for code in endpoints} - {None, ""}
    verified_endpoints = {code for pair in verified_pairs for code in pair}
    print(f"Checked {len(pairs):,} observed pairs across {len(endpoints):,} airports and "
          f"{len(countries):,} countries/regions (snapshot {snapshot_date}, latest period to {latest_observed})")
    print(f"Checked {sum(source_observations.values()):,} observations from {len(source_observations)} reporting sources, "
          f"{len(verified_pairs):,} verified nonstop pairs across {len(verified_endpoints):,} airports, "
          f"maximum distance error {max_distance_error:.2f} km")
    for identity in sorted(sources):
        if source_observations[identity]:
            print(f"  {identity}: {source_observations[identity]:,} observations, {source_verified[identity]:,} verified nonstop")
        else:
            print(f"  {identity}: compilation attribution")
    print(f"Verified HKG–DFW: {pairs['DFW', 'HKG']['distanceKm']:,.0f} km, "
          f"{hkg_dfw['flights']} movements ({hkg_dfw['period']})")
    print(f"Verified SIN–JFK: {pairs['JFK', 'SIN']['distanceKm']:,.0f} km, "
          f"{sin_jfk['flights']} reported movements, A350-900 listed ({sin_jfk['period']})")


def check_model_coverage(resources, airports):
    def read_airports(name):
        with (resources / f"{name}.json").open(encoding="utf-8") as source:
            return json.load(source)["airports"]

    def valid_runway(runway):
        return math.isfinite(runway["lengthM"]) and 1 < runway["lengthM"] <= 15_000

    sites = read_airports("airport-site-layouts")
    additions_path = resources / "airport-building-layouts.json"
    additions = read_airports("airport-building-layouts") if additions_path.is_file() else {}
    supplements = read_airports("airport-runway-supplements")
    terrains = read_airports("airport-site-terrain")
    assert (sites.keys() | additions.keys() | supplements.keys() | terrains.keys()) <= airports.keys(), "Unknown model airport ID"
    building_kinds = {"terminal", "tower", "hangar", "building"}
    layout_kinds = building_kinds | {"taxiway", "apron", "boundary"}
    for airport, features in sites.items():
        assert any(feature["kind"] == "terminal" and feature["area"] for feature in features), (
            f"Missing terminal footprint for {airport}"
        )
    for airport in sites.keys() | additions.keys():
        features = sites.get(airport, []) + additions.get(airport, [])
        keys = [(feature["kind"], feature["id"]) for feature in features]
        assert len(set(keys)) == len(keys), f"Duplicate site feature in {airport}"
        assert all(feature["kind"] in layout_kinds for feature in features), f"Unknown site feature in {airport}"
        assert all(
            -90 <= latitude <= 90 and -180 <= longitude <= 180
            for feature in features for latitude, longitude in feature["points"]
        ), f"Invalid site coordinates in {airport}"
        assert all(
            len(feature["points"]) >= (3 if feature["area"] else 1 if feature["kind"] == "tower" else 2)
            for feature in features
        ), f"Incomplete footprint in {airport}"
    for airport, runways in supplements.items():
        assert runways and all(valid_runway(runway) for runway in runways), f"Invalid supplemental runway in {airport}"
    for airport, grid in terrains.items():
        size = grid["size"]
        assert (3 <= size <= 33 and len(grid["elevationsM"]) == size * size
                and 100 <= grid["halfSpanM"] <= 10_000
                and all(-11_000 <= height <= 9_000 for height in grid["elevationsM"])), f"Invalid terrain in {airport}"
    runway_airports = {airport for airport, data in airports.items()
                       if any(valid_runway(runway) for runway in data.get("runways", []))}
    runway_airports.update(supplements)
    mapped_airports = sites.keys() | {
        airport for airport, features in additions.items() if any(feature["kind"] in building_kinds for feature in features)
    }
    terrain_only = airports.keys() - runway_airports - mapped_airports
    assert terrain_only <= terrains.keys(), f"Model coverage gap: {sorted(terrain_only - terrains.keys())}"
    print(f"Checked 3D coverage: {len(mapped_airports)} mapped layouts, {len(runway_airports - mapped_airports):,} runway models, "
          f"{len(terrain_only)} terrain-only models")


if __name__ == "__main__":
    catalog_path = Path(__file__).resolve().parent.parent / "App" / "Resources" / "airport-data.json"
    check_catalog(catalog_path)
