# HEIC test fixture

| Field | Value |
| --- | --- |
| File | `IMG_5296.HEIC` |
| Size | 5,924,047 bytes |
| Dimensions | 8064 × 6048 (48 MP) |
| Container | HEIC |
| Color | Display P3 |
| SHA-256 | `7edf1625cc05836dadb1749ad92860abc04ebb21e4848d587cf39cf345c5c2db` |
| Provenance | Original iPhone photo supplied by the project owner for test use. |

The file contains the iPhone 16/17 style metadata the converter appends to
(`hdrgainmap`, `semanticskymatte`, `linearthumbnail`, `styledeltamap`).
Slicing or re-encoding it with `sips` strips those auxiliary items, so tests
must use the unmodified bytes.

License: test fixture only, © the project owner. It is not covered by the
repository's MIT license and must not be redistributed outside this repository.

Integrity is checked by `LingXiIntegrationTests` before any conversion. A
mismatch fails the test instead of producing a misleading conversion result.
