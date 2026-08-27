"""Create a tiny, fully synthetic OpenFileGDB integration-test fixture."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import zipfile
from pathlib import Path

import numpy as np
from pyogrio.raw import write


def point(x: float, y: float) -> bytes:
    return struct.pack("<BIdd", 1, 1, x, y)


def line(points: list[tuple[float, float]]) -> bytes:
    payload = struct.pack("<BII", 1, 2, len(points))
    return payload + b"".join(struct.pack("<dd", *coordinate) for coordinate in points)


def polygon(ring: list[tuple[float, float]]) -> bytes:
    if ring[0] != ring[-1]:
        ring = [*ring, ring[0]]
    payload = struct.pack("<BIII", 1, 3, 1, len(ring))
    return payload + b"".join(struct.pack("<dd", *coordinate) for coordinate in ring)


def write_layer(
    destination: Path,
    name: str,
    geometry_type: str,
    geometries: list[bytes],
) -> None:
    count = len(geometries)
    write(
        destination,
        np.asarray(geometries, dtype=object),
        [
            np.arange(1, count + 1, dtype=np.int32),
            np.asarray([f"synthetic-{name}-{index}" for index in range(1, count + 1)]),
        ],
        ["synthetic_id", "label"],
        layer=name,
        driver="OpenFileGDB",
        geometry_type=geometry_type,
        crs="EPSG:9210",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)

    write_layer(
        destination,
        "sample_points",
        "Point",
        [point(500_000 + index * 10, 1_200_000 + index * 10) for index in range(3)],
    )
    write_layer(
        destination,
        "sample_lines",
        "LineString",
        [
            line([(500_000, 1_200_000), (500_050, 1_200_025)]),
            line([(500_010, 1_200_040), (500_070, 1_200_080)]),
        ],
    )
    write_layer(
        destination,
        "sample_polygons",
        "Polygon",
        [
            polygon(
                [
                    (500_000, 1_200_000),
                    (500_040, 1_200_000),
                    (500_040, 1_200_040),
                    (500_000, 1_200_040),
                ]
            )
        ],
    )

    expected = {
        "crs": "EPSG:9210",
        "layers": [
            {"name": "sample_points", "geometryType": "Point", "featureCount": 3},
            {"name": "sample_lines", "geometryType": "MultiLineString", "featureCount": 2},
            {"name": "sample_polygons", "geometryType": "MultiPolygon", "featureCount": 1},
        ],
    }
    destination.with_name("expected-catalog.json").write_text(
        json.dumps(expected, indent=2) + "\n", encoding="utf-8"
    )

    # A small AOI square (EPSG:9210, same CRS as the layers) covering the lower
    # left of the data: it fully contains points 0-1, clips line 0 and the
    # polygon, and misses point 2 and line 1 entirely.
    aoi = {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:EPSG::9210"}},
        "features": [
            {
                "type": "Feature",
                "properties": {},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [500_000, 1_200_000],
                        [500_015, 1_200_000],
                        [500_015, 1_200_015],
                        [500_000, 1_200_015],
                        [500_000, 1_200_000],
                    ]],
                },
            }
        ],
    }
    destination.with_name("sample-aoi.geojson").write_text(
        json.dumps(aoi, indent=2) + "\n", encoding="utf-8"
    )
    expected_clip = {
        "writtenLayerCount": 3,
        "layers": [
            {"sourceLayer": "sample_points", "status": "written",
             "candidateCount": 2, "outputCount": 2},
            {"sourceLayer": "sample_lines", "status": "written",
             "candidateCount": 1, "outputCount": 1},
            {"sourceLayer": "sample_polygons", "status": "written",
             "candidateCount": 1, "outputCount": 1},
        ],
    }
    destination.with_name("expected-clip.json").write_text(
        json.dumps(expected_clip, indent=2) + "\n", encoding="utf-8"
    )

    package_path = destination.with_name("sample.ppkx")
    with zipfile.ZipFile(package_path, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for file_path in sorted(destination.rglob("*")):
            if not file_path.is_file():
                continue
            relative = Path("commondata") / destination.name / file_path.relative_to(destination)
            archive_entry = zipfile.ZipInfo(relative.as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            archive_entry.compress_type = zipfile.ZIP_DEFLATED
            archive_entry.external_attr = 0o100644 << 16
            package.writestr(archive_entry, file_path.read_bytes())


if __name__ == "__main__":
    main()
