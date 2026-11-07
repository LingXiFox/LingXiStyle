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

## Privacy audit (2026-11-07)

The fixture was inspected with ImageIO/ExifTool-style metadata extraction before
this repository was treated as public. The audit recorded only whether fields
exist, not their values:

- GPS / location: **not present**; no latitude, longitude, or location name.
- Owner / author / creator / copyright: **no personal owner data**. The ICC
  profile contains Apple's standard color-profile notice, not an owner name.
- Device serial number or unique device identifier: **not present**.
- IPTC / XMP author, owner, credit, or rights fields: **not present**.
- Residual metadata: camera model, capture timestamp, lens/exposure data, and
  per-image MakerApple capture identifiers. These are inherent to an iPhone
  HEIC and do not identify the owner.
- Visual content: outdoor architecture and water with distant people; no
  close-up faces, private interior, documents, or other sensitive content.

Conclusion: no sensitive personal metadata was found. The original file and its
SHA-256 stay unchanged; no Git history rewrite is needed. Because the license
above permits test use only, do not use this image in App Store screenshots or
other marketing material without explicit permission from the owner.

Integrity is checked by `LingXiIntegrationTests` before any conversion. A
mismatch fails the test instead of producing a misleading conversion result.
