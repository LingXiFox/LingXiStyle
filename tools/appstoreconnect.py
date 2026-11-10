# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography"]
# ///
"""Local official App Store Connect client. Credentials never leave this process."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

BASE = "https://api.appstoreconnect.apple.com/v1/"
APP_ID = "6832474258"
PRODUCT_ID = "com.lingxifox.LingXiStyle.pro"
LOCALES = {"en-US": "en", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "ja": "ja"}
WRITE_ATTRIBUTES = {
    "appInfoLocalizations": {"locale", "name", "subtitle", "privacyPolicyUrl"},
    "appStoreVersionLocalizations": {"locale", "description", "promotionalText", "keywords", "supportUrl", "marketingUrl", "whatsNew"},
    "appStoreReviewDetails": {"notes", "demoAccountRequired", "contactFirstName", "contactLastName", "contactEmail", "contactPhone"},
    "appAssetLibraryImages": {"fileName", "fileSize", "category", "referenceName", "uploaded"},
    "appAssetLibraryPlacements": {"placementType", "placementGroup"},
    "appAssetLibraryPlacementOrderingRequests": {"placementGroup"},
}
RELEASE_ATTRIBUTES = {
    "apps": {"contentRightsDeclaration"},
    "appInfos": set(),
    "appStoreVersions": {"copyright", "usesIdfa"},
    "builds": {"usesNonExemptEncryption"},
    "ageRatingDeclarations": {
        "advertising", "alcoholTobaccoOrDrugUseOrReferences", "contests", "gambling",
        "gamblingSimulated", "gunsOrOtherWeapons", "healthOrWellnessTopics", "lootBox",
        "medicalOrTreatmentInformation", "messagingAndChat", "parentalControls", "profanityOrCrudeHumor",
        "ageAssurance", "sexualContentGraphicAndNudity", "sexualContentOrNudity", "socialMedia",
        "socialMediaAgeRestricted", "horrorOrFearThemes", "matureOrSuggestiveThemes", "unrestrictedWebAccess",
        "userGeneratedContent", "violenceCartoonOrFantasy", "violenceRealisticProlongedGraphicOrSadistic",
        "violenceRealistic", "ageRatingOverride", "ageRatingOverrideV2", "kidsAgeBand",
    },
    "inAppPurchases": {"name", "productId", "inAppPurchaseType", "reviewNote"},
    "inAppPurchaseVersions": set(),
    "inAppPurchaseLocalizations": {"locale", "name", "description"},
    "inAppPurchaseAppStoreReviewScreenshots": {"fileName", "fileSize", "sourceFileChecksum", "uploaded"},
    "appPriceSchedules": set(),
    "inAppPurchasePriceSchedules": set(),
    "appAvailabilities": {"availableInNewTerritories"},
    "territoryAvailabilities": {"available"},
    "inAppPurchaseAvailabilities": {"availableInNewTerritories"},
    "reviewSubmissions": {"platform"},
    "reviewSubmissionItems": set(),
}
V2_RESOURCES = {"inAppPurchases", "inAppPurchaseLocalizations", "appAvailabilities"}


def dump(value):
    return json.dumps(redact(value), ensure_ascii=False, indent=2)


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation preserves earlier previews and rollback evidence.
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w", encoding="utf-8") as handle:
        handle.write(dump(value) + "\n")


def relationship(kind, identifier):
    return {"data": {"type": kind, "id": identifier}}


def resource(kind, attrs, identifier=None, relationships=None):
    result = {"type": kind, "attributes": attrs}
    if identifier:
        result["id"] = identifier
    if relationships:
        result["relationships"] = relationships
    return {"data": result}


class ASCError(Exception):
    def __init__(self, status, errors):
        self.status, self.errors = status, errors
        super().__init__(f"HTTP {status}")


def redact(value):
    if isinstance(value, dict):
        return {k: ("[REDACTED]" if not isinstance(v, (bool, type(None))) and k.lower() in {
            "authorization", "uploadoperations", "assettoken", "templateurl",
            "demoaccountname", "demoaccountpassword", "contactfirstname",
            "contactlastname", "contactemail", "contactphonenumber", "contactphone",
        } else redact(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, str):
        value = re.sub(r"https://[^\s\"<>]+\?[^\s\"<>]+", "[SIGNED_URL_REDACTED]", value)
        value = re.sub(r"eyJ[\w-]+\.[\w-]+\.[\w-]+", "[JWT_REDACTED]", value)
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"):
            if os.environ.get(name):
                value = value.replace(os.environ[name], "[REDACTED]")
        return value
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, allow_v2=False, release_setup=False, signing_setup=False):
        self.allow_v2, self.release_setup = allow_v2, release_setup
        self.signing_setup = signing_setup
        config_path = Path.home() / ".config/appstoreconnect/config.json"
        config = json.loads(config_path.read_text()) if config_path.exists() else {}
        values = {k: os.environ.get(k) or config.get(k) for k in (
            "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH")}
        if not all(values.values()):
            raise ValueError("Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH locally.")
        self.secrets = list(values.values())
        self.key_id, self.issuer = values["ASC_KEY_ID"], values["ASC_ISSUER_ID"]
        path = Path(values["ASC_PRIVATE_KEY_PATH"]).expanduser().resolve()
        if not path.is_relative_to((Path.home()/".config/appstoreconnect/keys").resolve()):
            raise ValueError("Private key must be inside ~/.config/appstoreconnect/keys/.")
        self.key = serialization.load_pem_private_key(path.read_bytes(), password=None)
        if not isinstance(self.key, ec.EllipticCurvePrivateKey) or not isinstance(self.key.curve, ec.SECP256R1):
            raise ValueError("ES256 requires a P-256 private key.")
        self._token, self.expires = None, 0
        self.opener = urllib.request.build_opener(NoRedirect())

    def token(self):
        now = int(time.time())
        if now >= self.expires - 30:
            def b64(data):
                return base64.urlsafe_b64encode(data).rstrip(b"=")
            header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
            self.expires = now + 600
            payload = {"iss": self.issuer, "iat": now, "exp": self.expires, "aud": "appstoreconnect-v1"}
            message = b".".join(b64(json.dumps(v, separators=(",", ":")).encode()) for v in (header, payload))
            r, s = utils.decode_dss_signature(self.key.sign(message, ec.ECDSA(hashes.SHA256())))
            self._token = (message + b"." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()
        return self._token

    def request(self, method, path, body=None, params=None):
        if path.startswith("https://"):
            url = path
        elif path.startswith(("/v1/", "/v2/")):
            url = "https://api.appstoreconnect.apple.com" + path
        else:
            url = BASE + path.lstrip("/")
        parsed = urllib.parse.urlsplit(url)
        decoded_path = urllib.parse.unquote(parsed.path)
        allowed_version = decoded_path.startswith("/v1/") or (getattr(self, "allow_v2", False) and decoded_path.startswith("/v2/") and decoded_path.split("/")[2] in V2_RESOURCES)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or not allowed_version or ".." in decoded_path or parsed.fragment:
            raise ValueError("Official API version/resource not enabled; v2 requires explicit --allow-v2.")
        if method != "GET":
            parts = decoded_path.split("/")[2:]
            kind = parts[0]
            allowed = dict(WRITE_ATTRIBUTES)
            if getattr(self, "release_setup", False):
                allowed.update(RELEASE_ATTRIBUTES)
            if getattr(self, "signing_setup", False) and method == "POST":
                allowed.update(certificates={"csrContent", "certificateType"}, profiles={"name", "profileType"})
            build_link = getattr(self, "release_setup", False) and method == "PATCH" and len(parts) == 4 and parts[0] == "appStoreVersions" and parts[2:] == ["relationships", "build"]
            image_review = (getattr(self, 'creative_review_image', None) and method == 'PATCH'
                            and kind == 'reviewSubmissions' and len(parts) == 2)
            if image_review:
                expected = resource('reviewSubmissions', {'submitted': True}, parts[1])
                if body != expected:
                    raise ValueError('Only submission of the approved creative image is enabled.')
                draft = self.request('GET', 'reviewSubmissions/'+parts[1])['data']
                items = self.list('reviewSubmissions/'+parts[1]+'/items',
                    {'include': 'appAssetLibraryImage,appStoreVersion,inAppPurchaseVersion'})
                if draft['attributes']['state'] != 'READY_FOR_REVIEW' or draft['attributes'].get('submittedDate') or not items:
                    raise ValueError('Creative review draft is not editable or empty.')
                for item in items:
                    rels = item.get('relationships', {})
                    if (rels.get('appAssetLibraryImage', {}).get('data') or {}).get('id') != self.creative_review_image:
                        raise ValueError('Draft contains a resource other than the approved creative image.')
                    if any((value.get('data') or {}) for key, value in rels.items() if key not in {'appAssetLibraryImage', 'reviewSubmission'}):
                        raise ValueError('Mixed creative/App review submission is forbidden.')
            elif build_link:
                if not body or set(body) != {"data"} or body["data"].get("type") != "builds" or set(body["data"]) != {"type", "id"}:
                    raise ValueError("Only an existing build may be linked.")
            elif method not in {"POST", "PATCH"} or kind not in allowed or len(parts) != (1 if method == "POST" else 2):
                raise ValueError("Write blocked: only listing and screenshot operations are allowed.")
            elif not body or body.get("data", {}).get("type") != kind or set(body["data"].get("attributes", {})) - allowed[kind]:
                raise ValueError("Write blocked: unsupported resource attributes.")
            if kind in {"reviewSubmissions", "reviewSubmissionItems"} and method != "POST" and not image_review:
                raise ValueError("Only draft review preparation is allowed; submitting is blocked.")
            for key, value in body["data"].get("attributes", {}).items():
                if key.startswith("contact") and isinstance(value, str) and value:
                    self.secrets.append(value)
        if params:
            url += ("&" if parsed.query else "?") + urllib.parse.urlencode(params)
        for attempt in range(2):
            req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), method=method,
                headers={"Authorization": "Bearer " + self.token(), "Content-Type": "application/json", "Accept": "application/json"})
            try:
                with self.opener.open(req, timeout=60) as response:
                    data = response.read()
                    return json.loads(data) if data else {}
            except urllib.error.HTTPError as error:
                if error.code == 401 and attempt == 0:
                    self.expires = 0
                    continue
                try:
                    errors = json.loads(error.read()).get("errors", [])
                except (ValueError, AttributeError):
                    errors = [{"code": "NON_JSON_RESPONSE", "detail": "Response body omitted."}]
                safe = json.dumps(redact(errors))
                for secret in self.secrets:
                    safe = safe.replace(secret, "[REDACTED]")
                raise ASCError(error.code, json.loads(safe)) from None

    def list(self, path, params=None):
        result, seen = [], set()
        while path:
            if path in seen or len(seen) >= 100:
                raise ValueError("Pagination cycle or page limit reached.")
            seen.add(path)
            response = self.request("GET", path, params=params)
            result.extend(response["data"])
            path, params = response.get("links", {}).get("next"), None
        return result


def optional(client, path):
    try:
        return client.request("GET", path)["data"]
    except ASCError as error:
        if error.status == 404:
            return None
        raise


def target(client, app_id, version):
    apps = client.list("apps", {"filter[bundleId]": "com.lingxifox.Texel"})
    app = next((a for a in apps if a["id"] == app_id), None)
    if app is None or app["attributes"]["bundleId"] != "com.lingxifox.Texel":
        raise ValueError("Target app identity mismatch.")
    versions = client.list(f"apps/{app_id}/appStoreVersions")
    matches = [v for v in versions if v["attributes"]["versionString"] == version and v["attributes"]["platform"] == "IOS"]
    if len(matches) != 1:
        raise ValueError("Expected exactly one existing iOS target version.")
    return app, matches[0], versions


def diagnose(client, app_id, version):
    app, current, versions = target(client, app_id, version)
    infos = client.list(f"apps/{app_id}/appInfos")
    locals_ = client.list(f"appStoreVersions/{current['id']}/appStoreVersionLocalizations")
    review = optional(client, f"appStoreVersions/{current['id']}/appStoreReviewDetail")
    library = client.request("GET", f"apps/{app_id}/assetLibrary")["data"]
    images = client.list(f"appAssetLibraries/{library['id']}/images")
    placements = {loc["attributes"]["locale"]: client.list(
        f"appStoreVersionLocalizations/{loc['id']}/placements", {"include": "image", "sort": "placementGroupPosition"}) for loc in locals_}
    products = client.list(f"apps/{app_id}/inAppPurchasesV2")
    return {"app": app, "versions": versions, "target_version": current,
        "app_infos": infos, "app_info_localizations": {i["id"]: client.list(f"appInfos/{i['id']}/appInfoLocalizations") for i in infos},
        "version_localizations": locals_, "review": review,
        "review_contact_fields_present": {k: bool(review and review["attributes"].get(k)) for k in (
            "contactFirstName", "contactLastName", "contactEmail", "contactPhone")},
        "library": library, "images": images, "placements": placements,
        "iap": [p for p in products if p["attributes"]["productId"] == PRODUCT_ID],
        "availability": optional(client, f"apps/{app_id}/appAvailabilityV2")}


def parse_listing(text):
    sections = {}
    for heading, locale in (("English (U.S.)", "en-US"), ("简体中文（zh-Hans）", "zh-Hans"),
                            ("繁體中文（zh-Hant）", "zh-Hant"), ("日本語", "ja")):
        match = re.search(r"^## " + re.escape(heading) + r"\n(.*?)(?=^## |\Z)", text, re.M | re.S)
        if not match:
            raise ValueError("Missing listing section: " + locale)
        fields = {}
        for title, key, limit in (("Name", "name", 30), ("Subtitle", "subtitle", 30),
                ("Promotional Text", "promotionalText", 170), ("Keywords", "keywords", 100),
                ("Description", "description", 4000), ("What's New", "whatsNew", 4000)):
            found = re.search(r"^### " + re.escape(title) + r" \(\d+\)\s+```text\n(.*?)\n```", match[1], re.M | re.S)
            if not found or not found[1].strip() or len(found[1]) > limit or "<" in found[1] or "$$" in found[1]:
                raise ValueError(f"Missing, placeholder or oversized listing field: {locale}/{key}")
            fields[key] = found[1]
        sections[locale] = fields
    notes = re.search(r"^## Review notes \(English\)\s+```text\n(.*?)\n```", text, re.M | re.S)
    if not notes or len(notes[1]) > 4000 or "<" in notes[1]:
        raise ValueError("Missing or invalid review notes.")
    return sections, notes[1]


def listing_source(repo):
    def git(*args):
        return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()
    remote = git("remote", "get-url", "origin")
    if remote not in {"https://github.com/LingXiFox/LingXiStyle.git", "git@github.com:LingXiFox/LingXiStyle.git"}:
        raise ValueError("Expected LingXiFox/LingXiStyle origin.")
    git("fetch", "--quiet", "origin", "main")
    sha = git("rev-parse", "origin/main")
    text = git("show", sha + ":docs/app-store/listing.md") + "\n"
    source = {"repository": "LingXiFox/LingXiStyle", "commit": sha,
        "path": "docs/app-store/listing.md", "sha256": hashlib.sha256(text.encode()).hexdigest()}
    return source, text


def operation(kind, attrs, existing, collection, parent, locale=None):
    before = {k: existing["attributes"].get(k) for k in attrs} if existing else None
    changes = {k: v for k, v in attrs.items() if before is None or before[k] != v}
    if not changes:
        return None
    if existing:
        body = resource(kind, changes, existing["id"])
        path, method = kind + "/" + existing["id"], "PATCH"
    else:
        if locale:
            changes["locale"] = locale
        body = resource(kind, changes, relationships=parent)
        path, method = kind, "POST"
    return {"method": method, "path": path, "body": body, "before": before,
        "collection": collection, "locale": locale}


def metadata_plan(client, repo, app_id, version):
    source, text = listing_source(repo)
    listing, notes = parse_listing(text)
    state = diagnose(client, app_id, version)
    editable = [i for i in state["app_infos"] if i["attributes"].get("state", i["attributes"].get("appStoreState")) == "PREPARE_FOR_SUBMISSION"]
    if len(editable) != 1 or state["target_version"]["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
        raise ValueError("Target metadata is not unambiguously editable; review before writing.")
    info, current = editable[0], state["target_version"]
    info_locals = {l["attributes"]["locale"]: l for l in state["app_info_localizations"][info["id"]]}
    ver_locals = {l["attributes"]["locale"]: l for l in state["version_localizations"]}
    operations = []
    previous_release = any(v["id"] != current["id"] and v["attributes"]["appStoreState"] in {
        "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"} for v in state["versions"])
    for locale, fields in listing.items():
        info_attrs = {k: fields[k] for k in ("name", "subtitle")}
        info_attrs["privacyPolicyUrl"] = "https://apps.lingxifox.cn/texel/privacy/"
        operations.append(operation("appInfoLocalizations", info_attrs, info_locals.get(locale),
            f"appInfos/{info['id']}/appInfoLocalizations", {"appInfo": relationship("appInfos", info["id"])}, locale))
        attrs = {k: fields[k] for k in ("description", "promotionalText", "keywords")}
        attrs.update(supportUrl="https://apps.lingxifox.cn/texel/support/", marketingUrl="https://apps.lingxifox.cn/texel/")
        if previous_release:
            attrs["whatsNew"] = fields["whatsNew"]
        operations.append(operation("appStoreVersionLocalizations", attrs, ver_locals.get(locale),
            f"appStoreVersions/{current['id']}/appStoreVersionLocalizations",
            {"appStoreVersion": relationship("appStoreVersions", current["id"])}, locale))
    operations.append(operation("appStoreReviewDetails", {"notes": notes, "demoAccountRequired": False}, state["review"],
        f"appStoreVersions/{current['id']}/appStoreReviewDetail", {"appStoreVersion": relationship("appStoreVersions", current["id"]) }))
    return {"app_id": app_id, "version": version, "source": source,
        "notes": [] if previous_release else ["Initial release: omit whatsNew; repository release notes remain in the source."],
        "operations": [o for o in operations if o], "review_contact_fields_present": state["review_contact_fields_present"],
        "iap": state["iap"], "iap_creation_plan": None if state["iap"] else {
            "referenceName": "Texel Pro", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
            "localizations": {locale: {"name": "纹粒 Pro" if locale == "zh-Hans" else "Texel Pro", "description": description} for locale, description in {
                "en-US": "One-time purchase. Unlimited photos.", "zh-Hans": "一次购买，永久不限张数。",
                "zh-Hant": "一次購買，永久不限張數。", "ja": "一度の購入で、写真の枚数が無制限に。"}.items()},
            "requested_us_price": "2.99 USD (requires separate approval)", "action": "PLAN_ONLY"}}


def apply_plan(client, plan, journal, review_contact=None):
    _, current, _ = target(client, plan["app_id"], plan["version"])
    if current and current["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
        raise ValueError("Metadata parent is not editable.")
    contact = {}
    if review_contact:
        contact = json.loads(Path(review_contact).expanduser().read_text())
        required = {"contactFirstName", "contactLastName", "contactEmail", "contactPhone"}
        if set(contact) != required or not all(isinstance(v, str) and v.strip() and "<" not in v for v in contact.values()):
            raise ValueError("Review contact file needs exactly four nonempty contact fields.")
        if not re.fullmatch(r"\+\d[\d ()-]{5,24}", contact["contactPhone"]) or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", contact["contactEmail"]):
            raise ValueError("Invalid review email or international phone format.")
        client.secrets.extend(contact.values())
    results = []
    # Reserve the journal before any writes; a partial run remains visible on failure.
    journal = Path(journal)
    save(journal, results)
    def checkpoint():
        with journal.open("w", encoding="utf-8") as handle:
            handle.write(dump(results) + "\n")
    for op in plan["operations"]:
        try:
            desired = op["body"]["data"]["attributes"]
            if op["method"] == "PATCH":
                existing = client.request("GET", op["path"])["data"]
            else:
                if op["locale"]:
                    candidates = client.list(op["collection"])
                else:
                    single = optional(client, op["collection"])
                    candidates = [single] if single else []
                matches = [x for x in candidates if not op["locale"] or x["attributes"].get("locale") == op["locale"]]
                if len(matches) > 1:
                    raise ValueError("Ambiguous existing resource; refusing duplicate create.")
                existing = matches[0] if matches else None
            if existing and all(existing["attributes"].get(k) == v for k, v in desired.items()) and not (contact and op["body"]["data"]["type"] == "appStoreReviewDetails"):
                results.append({"path": op["path"], "status": "UNCHANGED"})
                checkpoint()
                continue
            if op["method"] == "PATCH" and any(existing["attributes"].get(k) != op["before"].get(k) for k in desired):
                raise ValueError("Concurrent metadata change detected; generate a fresh preview.")
            if existing and op["method"] == "POST":
                raise ValueError("Resource appeared since preview; generate a PATCH preview.")
            body = op["body"]
            if body["data"]["type"] == "appStoreReviewDetails":
                required = ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")
                contacts = contact
                if not contacts and existing:
                    contacts = {k: existing["attributes"].get(k) for k in required}
                if not all(contacts.get(k) for k in required):
                    raise ValueError("Review contacts missing; provide --review-contact locally before retrying.")
                desired = dict(desired, **contacts)
                body = dict(body, data=dict(body["data"], attributes=desired))
            response = client.request(op["method"], op["path"], body)["data"]
            confirmed = client.request("GET", response["type"] + "/" + response["id"])["data"]
            if not all(confirmed["attributes"].get(k) == v for k, v in desired.items()):
                raise ValueError("Metadata readback differs from requested values.")
            results.append({"path": op["path"], "status": "VERIFIED", "id": response["id"]})
        except ASCError as error:
            results.append({"path": op["path"], "http_status": error.status, "errors": error.errors})
        except ValueError as error:
            results.append({"path": op["path"], "error": str(error)})
        except (OSError, urllib.error.URLError):
            results.append({"path": op["path"], "error": "TRANSPORT_FAILURE: outcome unknown; reread state before retrying."})
            checkpoint()
            raise
        checkpoint()
    return results


def png_info(path):
    data = path.read_bytes()
    if path.suffix.lower() != ".png" or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Only reviewed RGB PNG screenshots are supported: " + path.name)
    offset, width, height, end, compressed = 8, None, None, False, bytearray()
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset+4:offset+8]
        content = data[offset+8:offset+8+length]
        if offset+12+length > len(data) or zlib.crc32(kind+content) & 0xffffffff != struct.unpack_from(">I", data, offset+8+length)[0]:
            raise ValueError("Corrupt PNG chunk: " + path.name)
        if offset == 8:
            if kind != b"IHDR" or length != 13:
                raise ValueError("Missing PNG header.")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", content)
            if depth != 8 or color != 2 or compression or filtering or interlace:
                raise ValueError("Screenshot must be non-interlaced 8-bit RGB without alpha.")
        if kind == b"tRNS":
            raise ValueError("PNG transparency is forbidden.")
        if kind == b"IDAT":
            compressed.extend(content)
        if kind == b"IEND":
            end = True
            break
        offset += length + 12
    if not end or not width or not height or width*height > 100_000_000:
        raise ValueError("Incomplete or excessive PNG dimensions.")
    expected = height*(width*3+1)
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(compressed, expected+1)
    if len(pixels) != expected or not decoder.eof or any(pixels[i] > 4 for i in range(0, expected, width*3+1)):
        raise ValueError("Corrupt PNG scanlines.")
    return {"path": str(path.resolve()), "fileName": path.name, "fileSize": len(data), "width": width,
        "height": height, "mode": "RGB", "sha256": hashlib.sha256(data).hexdigest()}


def match_spec(image, refdata):
    matches = []
    for spec in refdata["imageSpecs"]:
        d = spec["dimensions"]
        if "APP_SCREENSHOT" in spec["compatiblePlacementTypes"] and d["minWidth"] == d["maxWidth"] == image["width"] and d["minHeight"] == d["maxHeight"] == image["height"] and ".png" in spec["fileExtensions"] and "image/png" in spec["mimeTypes"] and image["fileSize"] <= spec["maxFileSize"]:
            matches.append(spec["specId"])
    placement = next(p for p in refdata["placementTypes"] if p["placementTypeId"] == "APP_SCREENSHOT")
    groups = [(m["placementGroupId"], spec) for m in placement["specMappings"] for spec in matches if spec in m["specs"]]
    if len(groups) != 1:
        raise ValueError("Screenshot does not match exactly one current Apple screenshot group.")
    group, spec = groups[0]
    feature = next(f for f in refdata["features"] if f["featureId"] == "APP_STORE_VERSIONS")
    policy = next(p for p in feature["placementPolicies"] if p["placementType"] == "APP_SCREENSHOT")
    limit = next(g["maxCount"] for g in policy["groupLimits"] if group in g["groupIds"])
    return {"group": group, "specId": spec, "limit": limit}


def find_image(image, assets):
    reference = "texel-" + image["locale"] + "-" + image["sha256"]
    matches = [a for a in assets if a["attributes"].get("referenceName") == reference]
    if not matches:
        # shortcut: browser assets have no checksum; use unique metadata until Apple exposes a source hash.
        matches = [a for a in assets if a["attributes"].get("fileName") == image["fileName"] and
            a["attributes"].get("fileSize") == image["fileSize"] and a["attributes"].get("specId") == image["specId"]]
    if len(matches) > 1:
        raise ValueError("Ambiguous existing image; refusing to upload a duplicate.")
    return matches[0] if matches else None


def screenshot_plan(client, root, app_id, version):
    _, current, _ = target(client, app_id, version)
    catalog = client.list("appAssetLibraryRefData")
    if len(catalog) != 1:
        raise ValueError("Unexpected Apple reference catalog.")
    ref = catalog[0]["attributes"]
    library = client.request("GET", f"apps/{app_id}/assetLibrary")["data"]
    assets = client.list(f"appAssetLibraries/{library['id']}/images")
    locals_ = {l["attributes"]["locale"]: l for l in client.list(f"appStoreVersions/{current['id']}/appStoreVersionLocalizations")}
    result = []
    for locale, directory in LOCALES.items():
        files = sorted((Path(root)/directory).glob("*.png"))
        if len(files) != 6:
            raise ValueError("Expected six reviewed PNGs for " + locale)
        if locale not in locals_:
            raise ValueError("Create version localization first: " + locale)
        placements = client.list(f"appStoreVersionLocalizations/{locals_[locale]['id']}/placements", {"include": "image", "sort": "placementGroupPosition"})
        for file in files:
            image = png_info(file)
            image.update(match_spec(image, ref), locale=locale, localization_id=locals_[locale]["id"])
            existing = find_image(image, assets)
            image["asset_id"] = existing["id"] if existing else None
            image["state"] = existing["attributes"]["state"] if existing else "NOT_UPLOADED"
            placed = [p for p in placements if existing and p.get("relationships", {}).get("image", {}).get("data", {}).get("id") == existing["id"] and p["attributes"]["placementGroup"] == image["group"] and p["attributes"]["placementType"] == "APP_SCREENSHOT"]
            if len(placed) > 1:
                raise ValueError("Duplicate placement already exists.")
            image["placement_id"] = placed[0]["id"] if placed else None
            image["placement_state"] = placed[0]["attributes"]["state"] if placed else None
            result.append(image)
        for group in {i["group"] for i in result if i["locale"] == locale}:
            wanted = [i for i in result if i["locale"] == locale and i["group"] == group]
            existing_count = sum(p["attributes"]["placementGroup"] == group and p["attributes"]["placementType"] == "APP_SCREENSHOT" for p in placements)
            if existing_count + sum(not i["placement_id"] for i in wanted) > wanted[0]["limit"]:
                raise ValueError("Group would exceed Apple's current screenshot limit.")
    return {"app_id": app_id, "version": version, "library_id": library["id"], "images": result}


def upload_parts(client, asset, path):
    operations = asset["attributes"].get("uploadOperations") or []
    expected_offset = 0
    for op in sorted(operations, key=lambda x: x["offset"]):
        url = urllib.parse.urlsplit(op["url"])
        if url.scheme != "https" or not url.hostname or not (url.hostname.endswith(".blobstore.apple.com") or url.hostname == "northamerica-1.object-storage.apple.com") or url.username or url.password or url.port not in {None, 443}:
            raise ValueError("Untrusted Apple asset upload host: " + (url.hostname or "<missing>"))
        if op["method"] != "PUT" or op["offset"] != expected_offset or op["length"] <= 0:
            raise ValueError("Invalid upload range or method.")
        expected_offset += op["length"]
    if not operations or expected_offset != path.stat().st_size:
        raise ValueError("Upload operations do not cover the complete file.")
    for op in operations:
        with path.open("rb") as handle:
            handle.seek(op["offset"])
            chunk = handle.read(op["length"])
        if len(chunk) != op["length"]:
            raise ValueError("Screenshot changed during upload.")
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        if any(h.lower() in {"authorization", "cookie", "proxy-authorization"} for h in headers):
            raise ValueError("Unexpected credentials in asset upload headers.")
        req = urllib.request.Request(op["url"], data=chunk, headers=headers, method="PUT")
        try:
            with client.opener.open(req, timeout=120) as response:
                response.read()
        except urllib.error.HTTPError as error:
            raise ASCError(error.code, [{"code": "ASSET_UPLOAD_FAILED", "detail": "Upload URL and body omitted; rerun to resume the same reservation."}]) from None


def apply_screenshots(client, plan, journal):
    _, current, _ = target(client, plan["app_id"], plan["version"])
    if current["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
        raise ValueError("Screenshot parent is not editable.")
    assets = client.list(f"appAssetLibraries/{plan['library_id']}/images")
    results = []
    for image in plan["images"]:
        if png_info(Path(image["path"]))["sha256"] != image["sha256"]:
            raise ValueError("Screenshot changed since preview.")
    journal = Path(journal)
    save(journal, results)
    def checkpoint():
        with journal.open("w", encoding="utf-8") as handle:
            handle.write(dump(results) + "\n")
    for image in plan["images"]:
        asset = find_image(image, assets)
        if not asset:
            attrs = {k: image[k] for k in ("fileName", "fileSize")}
            attrs.update(category="APP_SCREENSHOTS_AND_PREVIEWS", referenceName="texel-"+image["locale"]+"-"+image["sha256"])
            asset = client.request("POST", "appAssetLibraryImages", resource("appAssetLibraryImages", attrs,
                relationships={"assetLibrary": relationship("appAssetLibraries", plan["library_id"])}))["data"]
            assets.append(asset)
        path = "appAssetLibraryImages/" + asset["id"]
        asset = client.request("GET", path)["data"]
        if asset["attributes"]["state"] == "AWAITING_UPLOAD":
            upload_parts(client, asset, Path(image["path"]))
            client.request("PATCH", path, resource("appAssetLibraryImages", {"uploaded": True}, asset["id"]))
        deadline = time.monotonic() + 120
        while True:
            asset = client.request("GET", path)["data"]
            state = asset["attributes"]["state"]
            if state != "UPLOAD_COMPLETE" or time.monotonic() >= deadline:
                break
            time.sleep(5)
        if state not in {"PREPARE_FOR_SUBMISSION", "APPROVED"}:
            raise ValueError("Apple image not ready: " + state + "; rerun to resume, no resource was deleted.")
        actual = asset["attributes"]
        dimensions = actual.get("imageAsset") or {}
        if actual.get("specId") != image["specId"] or (dimensions.get("width"), dimensions.get("height")) != (image["width"], image["height"]):
            raise ValueError("Apple processed screenshot specification mismatch.")
        placements = client.list(f"appStoreVersionLocalizations/{image['localization_id']}/placements", {"include": "image", "sort": "placementGroupPosition"})
        matches = [p for p in placements if p.get("relationships", {}).get("image", {}).get("data", {}).get("id") == asset["id"] and p["attributes"]["placementGroup"] == image["group"] and p["attributes"]["placementType"] == "APP_SCREENSHOT"]
        if not matches:
            if sum(p["attributes"]["placementGroup"] == image["group"] and p["attributes"]["placementType"] == "APP_SCREENSHOT" for p in placements) >= image["limit"]:
                raise ValueError("Placement limit reached since preview.")
            placement = client.request("POST", "appAssetLibraryPlacements", resource("appAssetLibraryPlacements",
                {"placementType": "APP_SCREENSHOT", "placementGroup": image["group"]}, relationships={
                    "image": relationship("appAssetLibraryImages", asset["id"]),
                    "appStoreVersionLocalization": relationship("appStoreVersionLocalizations", image["localization_id"])}))["data"]
        elif len(matches) == 1:
            placement = matches[0]
        else:
            raise ValueError("Duplicate placements; manual review required.")
        results.append({"locale": image["locale"], "fileName": image["fileName"], "asset_id": asset["id"],
            "asset_state": state, "placement_id": placement["id"], "placement_state": placement["attributes"]["state"],
            "group": image["group"], "localization_id": image["localization_id"]})
        checkpoint()
        print(dump(results[-1]), flush=True)
    for locale in LOCALES:
        wanted = [r for r in results if r["locale"] == locale]
        for group in {r["group"] for r in wanted}:
            group_results = [r for r in wanted if r["group"] == group]
            loc = group_results[0]["localization_id"]
            current = client.list(f"appStoreVersionLocalizations/{loc}/placements", {"include": "image", "sort": "placementGroupPosition"})
            ordered = [r["placement_id"] for r in group_results]
            present = [p["id"] for p in current if p["attributes"]["placementGroup"] == group and p["attributes"]["placementType"] == "APP_SCREENSHOT"]
            ordered += [p for p in present if p not in ordered]
            if ordered != present:
                body = resource("appAssetLibraryPlacementOrderingRequests", {"placementGroup": group}, relationships={
                    "orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": p} for p in ordered]},
                    "appStoreVersionLocalization": relationship("appStoreVersionLocalizations", loc)})
                client.request("POST", "appAssetLibraryPlacementOrderingRequests", body)
                after = client.list(f"appStoreVersionLocalizations/{loc}/placements", {"include": "image", "sort": "placementGroupPosition"})
                if [p["id"] for p in after if p["attributes"]["placementGroup"] == group and p["attributes"]["placementType"] == "APP_SCREENSHOT"] != ordered:
                    raise ValueError("Screenshot order readback mismatch.")
    checkpoint()
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", default=APP_ID)
    parser.add_argument("--version", default="1.7.1")
    parser.add_argument("--allow-v2", action="store_true", help="Explicitly allow official IAP/availability v2 endpoints.")
    parser.add_argument("--release-setup", action="store_true", help="Enable separately approved metadata/market changes; App version submission stays blocked.")
    parser.add_argument("--signing-setup", action="store_true", help="Explicitly permit creating local distribution certificates/profiles; never revokes.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test", help="Run offline regression tests without loading credentials.")
    raw = sub.add_parser("request", help="Official GET, POST or PATCH; writes require --apply.")
    raw.add_argument("method", choices=["GET", "POST", "PATCH"])
    raw.add_argument("path")
    raw.add_argument("--body", type=Path)
    raw.add_argument("--apply", action="store_true")
    diagnostic = sub.add_parser("diagnose", help="Read-only app, version, localization, review, image and IAP inventory.")
    diagnostic.add_argument("--output", type=Path)
    planning = sub.add_parser("plan", help="Read GitHub main listing and preview metadata changes.")
    planning.add_argument("--repo", type=Path, default=Path.cwd())
    planning.add_argument("--output", type=Path, required=True)
    apply = sub.add_parser("apply", help="Apply a reviewed metadata preview with readback.")
    apply.add_argument("plan", type=Path)
    apply.add_argument("--journal", type=Path, required=True)
    apply.add_argument("--review-contact", type=Path, help="Local-only JSON with the four real review contact fields.")
    screenshots = sub.add_parser("screenshots", help="Preview image validation and existing assets; --apply-plan uploads.")
    screenshots.add_argument("--root", type=Path, default=Path("AppStoreScreenshots/ASC"))
    screenshots.add_argument("--output", type=Path)
    screenshots.add_argument("--apply-plan", type=Path)
    screenshots.add_argument("--journal", type=Path)
    from release_appstore import add_parser
    add_parser(sub)
    args = parser.parse_args()
    try:
        if args.command == "self-test":
            import unittest
            suite = unittest.defaultTestLoader.discover(str(Path(__file__).parent), pattern="test_appstoreconnect.py")
            return int(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
        client = Client(args.allow_v2, args.release_setup, args.signing_setup)
        if args.command == "release":
            from release_appstore import execute
            result = execute(args, client)
        elif args.command == "request":
            body = json.loads(args.body.read_text()) if args.body else None
            if args.method != "GET" and not args.apply:
                print(dump({"preview": True, "method": args.method, "path": args.path, "body": body}))
                return 0
            result = client.request(args.method, args.path, body)
        elif args.command == "diagnose":
            result = diagnose(client, args.app_id, args.version)
            if args.output:
                save(args.output, result)
        elif args.command == "plan":
            result = metadata_plan(client, args.repo, args.app_id, args.version)
            save(args.output, result)
        elif args.command == "apply":
            result = apply_plan(client, json.loads(args.plan.read_text()), args.journal, args.review_contact)
            print(dump(result))
            return int(any(r.get("status") not in {"VERIFIED", "UNCHANGED"} for r in result))
        else:
            if args.apply_plan:
                if not args.journal:
                    raise ValueError("--journal is required when applying screenshots.")
                result = apply_screenshots(client, json.loads(args.apply_plan.read_text()), args.journal)
            else:
                if not args.output:
                    raise ValueError("--output is required for screenshot preview.")
                result = screenshot_plan(client, args.root, args.app_id, args.version)
                save(args.output, result)
        print(dump(result))
    except ASCError as error:
        print(json.dumps({"http_status": error.status, "errors": error.errors}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    except ValueError as error:
        print(dump({"error": "INVALID_INPUT", "detail": str(error)}), file=sys.stderr)
        return 1
    except Exception as error:
        print(dump({"error": type(error).__name__, "detail": "Local configuration, input or transport failure; sensitive details omitted."}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
