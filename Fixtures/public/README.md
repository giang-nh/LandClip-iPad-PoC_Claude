# Public OpenFileGDB fixture

`sample.gdb` is fully synthetic test data created by
`scripts/create_public_fixture.py`. It contains no geometry, attributes, names,
or identifiers copied from production/customer data.

The fixture deliberately covers three vector geometry families using EPSG:9210:

- `sample_points`: 3 points
- `sample_lines`: 2 multi-lines
- `sample_polygons`: 1 multi-polygon

`expected-catalog.json` is the expected result for the native OpenFileGDB
integration test. This fixture may be used and redistributed with this project.
`sample.ppkx` contains only this synthetic GDB and exercises the complete native
copy, ZIP extraction, GDB discovery, and catalog pipeline.
