# Third-party licenses

LandClip iPad PoC links five native libraries, built from source by
[`scripts/build-native-xcframeworks.sh`](../scripts/build-native-xcframeworks.sh)
and packaged as XCFrameworks in `Vendor/`. It also bundles the PROJ and GDAL
runtime data trees at the app-bundle root.

The full upstream license text of each component is reproduced verbatim in this
directory. See [`docs/DEPENDENCIES.md`](../docs/DEPENDENCIES.md) for the pinned
versions, SHA-256 digests and the build configuration.

| Component | Version | License | Text |
|---|---|---|---|
| GDAL | 3.11.4 | MIT (X/MIT style) | [`GDAL-3.11.4-LICENSE.txt`](GDAL-3.11.4-LICENSE.txt) |
| PROJ | 9.6.2 | MIT | [`PROJ-9.6.2-COPYING.txt`](PROJ-9.6.2-COPYING.txt) |
| GEOS | 3.14.1 | LGPL-2.1-only | [`GEOS-3.14.1-COPYING.txt`](GEOS-3.14.1-COPYING.txt) |
| SQLite | 3.50.4 | Public Domain | [`SQLite-3.50.4-LICENSE.txt`](SQLite-3.50.4-LICENSE.txt) |
| libarchive | 3.8.9 | BSD-2-Clause (+ BSD-3 / public-domain / CC0 parts) | [`libarchive-3.8.9-COPYING.txt`](libarchive-3.8.9-COPYING.txt) |

Bundled data:

- **PROJ data** (`proj.db`, `proj.ini`): derived from the EPSG Dataset (and ESRI,
  IGNF, …). Redistribution is permitted **with attribution to EPSG**; the data
  must not be modified and still called "EPSG". Source-build data only — no
  network-downloaded grids (`BUILD_PROJSYNC=OFF`, `ENABLE_CURL=OFF`).
- **GDAL data**: MIT, with reference tables partly derived from the EPSG Dataset
  (same attribution note).

An "Acknowledgements" / "Legal" screen in the shipping app must surface at least:
the five component names + versions, a pointer to these license texts, and the
EPSG attribution.

## GEOS (LGPL-2.1) — compliance status

GEOS is currently linked **statically** (into `libgdal.a` via `GDAL_USE_GEOS=ON`,
then into the app binary). The catalog code in this PoC does not call GEOS yet;
it is retained because Phase 3 (the AOI spatial engine) needs it.

**Current status:** this PoC is *not distributed* — it is built and tested only on
CI for internal evaluation (see `docs/02_product_requirement.md`: "Đối tượng dùng
ban đầu: Nội bộ, số lượng nhỏ"). Static linking is acceptable in that state.

**Before ANY distribution** (App Store, TestFlight, ad-hoc, enterprise), LGPL-2.1
§6 must be satisfied by one of:

1. Ship GEOS as a **dynamic** framework (`.framework` / dylib the user could swap),
   or
2. Provide a **relinkable object-code kit** — the app's `.o` files plus a link
   script — so a user can rebuild the app against a modified GEOS, and include a
   prominent notice + this LGPL-2.1 text.

Option 1 is the intended path and should be decided as part of the Phase 3
architecture. Until then, do not distribute a build produced with the current
static configuration.
