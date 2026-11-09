"""Offline regression checks; never reads production credentials or contacts Apple."""
import base64
import contextlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import zlib

import appstoreconnect as asc
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils


def client():
    value = asc.Client.__new__(asc.Client)
    value.key = ec.generate_private_key(ec.SECP256R1())
    value.key_id, value.issuer = "test-key", "test-issuer"
    value._token, value.expires, value.secrets = None, 0, ["test-key", "test-issuer"]
    return value


class FakeResponse(io.BytesIO):
    pass


class FakeOpener:
    def __init__(self, responses):
        self.responses, self.requests = iter(responses), []

    def open(self, req, timeout):
        self.requests.append(req)
        value = next(self.responses)
        if isinstance(value, Exception):
            raise value
        return FakeResponse(json.dumps(value).encode())


def http_error(status, payload):
    return urllib.error.HTTPError(asc.BASE, status, "test", {}, io.BytesIO(json.dumps(payload).encode()))


class ClientTests(unittest.TestCase):
    def test_jwt_real_signature_claims_cache_and_expiry(self):
        c = client()
        with patch.object(asc.time, "time", return_value=1000):
            token = c.token()
            self.assertEqual(c.token(), token)
        header, body, sig = token.split(".")
        decode = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
        self.assertEqual(json.loads(decode(header)), {"alg": "ES256", "kid": "test-key", "typ": "JWT"})
        self.assertEqual(json.loads(decode(body)), {"iss": "test-issuer", "iat": 1000, "exp": 1600, "aud": "appstoreconnect-v1"})
        raw = decode(sig)
        self.assertEqual(len(raw), 64)
        signature = utils.encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
        c.key.public_key().verify(signature, (header+"."+body).encode(), ec.ECDSA(hashes.SHA256()))
        with patch.object(asc.time, "time", return_value=1571):
            self.assertNotEqual(c.token(), token)

    def test_401_refreshes_once_and_409_never_retries(self):
        c = client()
        c.opener = FakeOpener([http_error(401, {}), {"data": []}])
        self.assertEqual(c.request("GET", "apps"), {"data": []})
        self.assertEqual(len(c.opener.requests), 2)
        c.opener = FakeOpener([http_error(409, {"errors": [{"code": "INVALID", "detail": "test-key", "source": {"pointer": "/data/attributes/name"}}]})])
        with self.assertRaises(asc.ASCError) as caught:
            c.request("PATCH", "appInfoLocalizations/id", asc.resource("appInfoLocalizations", {"name": "Texel"}, "id"))
        self.assertEqual(len(c.opener.requests), 1)
        self.assertEqual(caught.exception.errors[0], {"code": "INVALID", "detail": "[REDACTED]", "source": {"pointer": "/data/attributes/name"}})

    def test_repeated_401_stops(self):
        c = client()
        c.opener = FakeOpener([http_error(401, {}), http_error(401, {})])
        with self.assertRaises(asc.ASCError):
            c.request("GET", "apps")
        self.assertEqual(len(c.opener.requests), 2)

    def test_host_paths_and_dangerous_writes_blocked_before_network(self):
        c = client()
        for path in ("https://evil.example/v1/apps", "https://api.appstoreconnect.apple.com.evil/v1/apps", "../iris/v1/apps", "https://api.appstoreconnect.apple.com/iris/v1/apps", "%2e%2e/v2/apps"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                c.request("GET", path)
        for method, path, body in (("DELETE", "appAssetLibraryImages/id", None),
                ("POST", "reviewSubmissions", asc.resource("reviewSubmissions", {})),
                ("PATCH", "apps/id", asc.resource("apps", {"primaryLocale": "ja"})),
                ("PATCH", "appAssetLibraryImages/id", asc.resource("appAssetLibraryImages", {"archived": True}, "id")),
                ("POST", "inAppPurchasePrices", asc.resource("inAppPurchasePrices", {}))):
            with self.subTest(path=path), self.assertRaises(ValueError):
                c.request(method, path, body)

    def test_pagination_and_cycle(self):
        c = client()
        c.opener = FakeOpener([{"data": [1], "links": {"next": asc.BASE+"apps?cursor=2"}}, {"data": [2]}])
        self.assertEqual(c.list("apps"), [1, 2])
        c.opener = FakeOpener([{"data": [], "links": {"next": "apps"}}])
        with self.assertRaises(ValueError):
            c.list("apps")

    def test_redaction(self):
        result = asc.redact({"contactPhone": "+1234567", "contactEmail": "private@example.com", "contactFirstName": True,
            "uploadOperations": [{"url": "https://store.blobstore.apple.com/path?secret=x"}], "detail": "eyJabc.def.ghi"})
        self.assertNotIn("private@example", json.dumps(result))
        self.assertNotIn("1234567", json.dumps(result))
        self.assertTrue(result["contactFirstName"])
        self.assertEqual(result["detail"], "[JWT_REDACTED]")

    def test_v2_is_explicit_and_scoped_to_approved_resources(self):
        c = client()
        with self.assertRaises(ValueError):
            c.request("GET", "/v2/inAppPurchases/item")
        c.allow_v2 = True
        c.opener = FakeOpener([{"data": []}])
        c.request("GET", "/v2/inAppPurchases/item")
        self.assertEqual(c.opener.requests[0].full_url, "https://api.appstoreconnect.apple.com/v2/inAppPurchases/item")
        with self.assertRaises(ValueError):
            c.request("GET", "/v2/certificates")

    def test_release_writes_require_flag_and_never_submit(self):
        c = client()
        body = asc.resource("ageRatingDeclarations", {"advertising": False}, "id")
        with self.assertRaises(ValueError):
            c.request("PATCH", "ageRatingDeclarations/id", body)
        c.release_setup = True
        c.opener = FakeOpener([{"data": {}}])
        c.request("PATCH", "ageRatingDeclarations/id", body)
        for method, path, data in (("PATCH", "reviewSubmissions/id", {"submitted": True}),
                ("POST", "reviewSubmissions", {"platform": "IOS", "submitted": True}),
                ("POST", "appStoreVersionSubmissions", {}),
                ("POST", "appStoreVersionReleaseRequests", {})):
            with self.subTest(path=path), self.assertRaises(ValueError):
                c.request(method, path, asc.resource(path.split('/')[0], data))

    def test_build_attachment_is_only_enabled_relationship_write(self):
        c = client()
        c.release_setup = True
        c.opener = FakeOpener([{}])
        c.request("PATCH", "appStoreVersions/id/relationships/build", {"data": {"type": "builds", "id": "build"}})
        with self.assertRaises(ValueError):
            c.request("PATCH", "appStoreVersions/id/relationships/appStoreVersionSubmission", {"data": {"type": "appStoreVersionSubmissions", "id": "id"}})

    def test_release_draft_review_create_is_allowed_without_submission(self):
        c = client()
        c.release_setup = True
        c.opener = FakeOpener([{"data": {"id": "draft"}}])
        result = c.request("POST", "reviewSubmissions", asc.resource("reviewSubmissions", {"platform": "IOS"}, relationships={"app": asc.relationship("apps", asc.APP_ID)}))
        self.assertEqual(result["data"]["id"], "draft")


class MetadataTests(unittest.TestCase):
    def test_missing_localization_creates_once_and_appeared_resource_stops(self):
        new = {"id": "id", "type": "appInfoLocalizations", "attributes": {"name": "Texel", "locale": "ja"}}
        op = asc.operation("appInfoLocalizations", {"name": "Texel"}, None, "collection", {"appInfo": asc.relationship("appInfos", "parent")}, "ja")
        plan = {"app_id": asc.APP_ID, "version": "1.7.1", "operations": [op]}
        for candidates, expected in (([], "VERIFIED"), ([dict(new, attributes={"name": "Other", "locale": "ja"})], None)):
            c = client()
            c.opener = FakeOpener([{"data": candidates}, {"data": new}, {"data": new}])
            with tempfile.TemporaryDirectory() as directory, patch.object(asc, "target", return_value=(None, None, [])):
                result = asc.apply_plan(c, plan, Path(directory)/"journal.json")
            self.assertEqual(result[0].get("status"), expected)
            self.assertEqual(sum(r.method == "POST" for r in c.opener.requests), 1 if not candidates else 0)

    def test_missing_review_404_creates_with_local_contacts(self):
        fields = {"contactFirstName": "Test", "contactLastName": "Reviewer", "contactEmail": "test@example.com", "contactPhone": "+12025550123"}
        new = {"id": "review", "type": "appStoreReviewDetails", "attributes": {"notes": "Notes", **fields}}
        op = asc.operation("appStoreReviewDetails", {"notes": "Notes"}, None, "missing-review", {"appStoreVersion": asc.relationship("appStoreVersions", "parent")})
        c = client()
        c.opener = FakeOpener([http_error(404, {}), {"data": new}, {"data": new}])
        with tempfile.TemporaryDirectory() as directory, patch.object(asc, "target", return_value=(None, None, [])):
            contact = Path(directory)/"contact.json"
            contact.write_text(json.dumps(fields))
            result = asc.apply_plan(c, {"app_id": asc.APP_ID, "version": "1.7.1", "operations": [op]}, Path(directory)/"journal.json", contact)
        self.assertEqual(result[0]["status"], "VERIFIED")
        self.assertEqual([r.method for r in c.opener.requests], ["GET", "POST", "GET"])

    def test_review_contact_local_only_and_readback(self):
        fields = {"contactFirstName": "Test", "contactLastName": "Reviewer", "contactEmail": "test@example.com", "contactPhone": "+12025550123"}
        old = {"id": "review", "type": "appStoreReviewDetails", "attributes": {"notes": None, **{k: None for k in fields}}}
        new = dict(old, attributes={"notes": "Real notes", **fields})
        op = asc.operation("appStoreReviewDetails", {"notes": "Real notes"}, old, "collection", {})
        plan = {"app_id": asc.APP_ID, "version": "1.7.1", "operations": [op]}
        c = client()
        c.opener = FakeOpener([{"data": old}, {"data": new}, {"data": new}])
        with tempfile.TemporaryDirectory() as directory, patch.object(asc, "target", return_value=(None, None, [])):
            contact = Path(directory)/"contact.json"
            contact.write_text(json.dumps(fields))
            journal = Path(directory)/"journal.json"
            result = asc.apply_plan(c, plan, journal, contact)
            self.assertEqual(result[0]["status"], "VERIFIED")
            self.assertNotIn(fields["contactEmail"], journal.read_text())
        body = json.loads(c.opener.requests[1].data)
        self.assertEqual(body["data"]["attributes"]["contactPhone"], fields["contactPhone"])

    def test_missing_review_contacts_fail_before_patch(self):
        old = {"id": "review", "type": "appStoreReviewDetails", "attributes": {"notes": None}}
        op = asc.operation("appStoreReviewDetails", {"notes": "Notes"}, old, "collection", {})
        c = client()
        c.opener = FakeOpener([{"data": old}])
        with tempfile.TemporaryDirectory() as directory, patch.object(asc, "target", return_value=(None, None, [])):
            result = asc.apply_plan(c, {"app_id": asc.APP_ID, "version": "1.7.1", "operations": [op]}, Path(directory)/"journal.json")
        self.assertIn("Review contacts missing", result[0]["error"])
        self.assertEqual(len(c.opener.requests), 1)

    def test_real_listing_four_languages_and_limits(self):
        text = (Path(__file__).resolve().parents[1]/"docs/app-store/listing.md").read_text()
        listing, notes = asc.parse_listing(text)
        self.assertEqual(set(listing), set(asc.LOCALES))
        self.assertEqual(listing["en-US"]["name"], "Texel - Texture & Grain")
        self.assertIn(asc.PRODUCT_ID, notes)
        with self.assertRaises(ValueError):
            asc.parse_listing(text.replace("原 Asset 不会", "原 Asset $$  $$不会"))

    def test_existing_resource_patch_missing_resource_post_noop(self):
        existing = {"id": "id", "attributes": {"name": "Old", "subtitle": "Same"}}
        op = asc.operation("appInfoLocalizations", {"name": "New", "subtitle": "Same"}, existing, "collection", {}, "ja")
        self.assertEqual(op["method"], "PATCH")
        self.assertEqual(op["body"]["data"]["attributes"], {"name": "New"})
        self.assertIsNone(asc.operation("appInfoLocalizations", {"name": "Old"}, existing, "collection", {}))
        op = asc.operation("appInfoLocalizations", {"name": "New"}, None, "collection", {"appInfo": asc.relationship("appInfos", "id")}, "ja")
        self.assertEqual(op["method"], "POST")
        self.assertEqual(op["body"]["data"]["attributes"]["locale"], "ja")

    def test_apply_idempotence_stale_preview_and_readback(self):
        old = {"id": "id", "type": "appInfoLocalizations", "attributes": {"name": "Old"}}
        new = dict(old, attributes={"name": "New"})
        op = asc.operation("appInfoLocalizations", {"name": "New"}, old, "collection", {})
        plan = {"app_id": asc.APP_ID, "version": "1.7.1", "operations": [op]}
        for responses, expected, writes in (([old, new, new], "VERIFIED", 1), ([new], "UNCHANGED", 0),
                ([dict(old, attributes={"name": "Other"})], None, 0), ([old, new, old], None, 1)):
            c = client()
            c.opener = FakeOpener([{"data": r} for r in responses])
            with tempfile.TemporaryDirectory() as directory, patch.object(asc, "target", return_value=(None, None, [])):
                result = asc.apply_plan(c, plan, Path(directory)/"journal.json")
            self.assertEqual(result[0].get("status"), expected)
            self.assertEqual(sum(r.method != "GET" for r in c.opener.requests), writes)


def png(width=2, height=2, color=2, extra=b""):
    def chunk(kind, body):
        return struct.pack(">I", len(body))+kind+body+struct.pack(">I", zlib.crc32(kind+body) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0))+extra+chunk(b"IDAT", zlib.compress((b"\0"+b"\0"*(width*3))*height))+chunk(b"IEND", b"")


class ScreenshotTests(unittest.TestCase):
    def test_existing_ready_screenshot_rerun_does_not_write(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"home.png"
            path.write_bytes(png())
            image = dict(asc.png_info(path), locale="ja", specId="spec", group="group", limit=10, localization_id="loc")
            asset = {"id": "existing", "type": "appAssetLibraryImages", "attributes": {
                "fileName": path.name, "fileSize": image["fileSize"], "specId": "spec", "state": "PREPARE_FOR_SUBMISSION", "imageAsset": {"width": 2, "height": 2}}}
            placement = {"id": "placement", "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": "group", "state": "ACTIVE"}, "relationships": {"image": asc.relationship("appAssetLibraryImages", "existing")}}
            c = client()
            c.opener = FakeOpener([{"data": [asset]}, {"data": asset}, {"data": asset}, {"data": [placement]}, {"data": [placement]}])
            with patch.object(asc, "target", return_value=(None, {"attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}}, [])), contextlib.redirect_stdout(io.StringIO()):
                result = asc.apply_screenshots(c, {"app_id": asc.APP_ID, "version": "1.7.1", "library_id": "library", "images": [image]}, Path(directory)/"journal.json")
            self.assertEqual(result[0]["asset_state"], "PREPARE_FOR_SUBMISSION")
            self.assertTrue(all(r.method == "GET" for r in c.opener.requests))

    def test_resume_awaiting_reservation_uploads_and_commits_once(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"home.png"
            path.write_bytes(png())
            image = dict(asc.png_info(path), locale="ja", specId="spec", group="group", limit=10, localization_id="loc")
            ready = {"id": "existing", "type": "appAssetLibraryImages", "attributes": {
                "referenceName": "texel-ja-"+image["sha256"], "fileName": path.name, "fileSize": image["fileSize"], "specId": "spec", "state": "PREPARE_FOR_SUBMISSION", "imageAsset": {"width": 2, "height": 2}}}
            waiting = dict(ready, attributes=dict(ready["attributes"], state="AWAITING_UPLOAD"))
            placement = {"id": "placement", "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": "group", "state": "ACTIVE"}, "relationships": {"image": asc.relationship("appAssetLibraryImages", "existing")}}
            c = client()
            c.opener = FakeOpener([{"data": [waiting]}, {"data": waiting}, {"data": ready}, {"data": ready}, {"data": [placement]}, {"data": [placement]}])
            with patch.object(asc, "target", return_value=(None, {"attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}}, [])), patch.object(asc, "upload_parts") as upload, contextlib.redirect_stdout(io.StringIO()):
                asc.apply_screenshots(c, {"app_id": asc.APP_ID, "version": "1.7.1", "library_id": "library", "images": [image]}, Path(directory)/"journal.json")
            upload.assert_called_once()
            writes = [r for r in c.opener.requests if r.method != "GET"]
            self.assertEqual(len(writes), 1)
            self.assertEqual(json.loads(writes[0].data)["data"]["attributes"], {"uploaded": True})

    def test_png_validation_rejects_alpha_crc_and_truncation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"screenshot.png"
            path.write_bytes(png())
            info = asc.png_info(path)
            self.assertEqual((info["width"], info["height"], info["mode"]), (2, 2, "RGB"))
            for bad in (png(color=6), png()[:-12], png()[:30]+b"wrongcrc"+png()[38:]):
                path.write_bytes(bad)
                with self.assertRaises(ValueError):
                    asc.png_info(path)

    def test_spec_is_fetched_and_not_guessed(self):
        ref = {"imageSpecs": [{"specId": "dynamic-spec", "dimensions": {"minWidth": 2, "maxWidth": 2, "minHeight": 2, "maxHeight": 2},
            "compatiblePlacementTypes": ["APP_SCREENSHOT"], "fileExtensions": [".png"], "mimeTypes": ["image/png"], "maxFileSize": 1000}],
            "placementTypes": [{"placementTypeId": "APP_SCREENSHOT", "specMappings": [{"placementGroupId": "new-group", "specs": ["dynamic-spec"]}]}],
            "features": [{"featureId": "APP_STORE_VERSIONS", "placementPolicies": [{"placementType": "APP_SCREENSHOT", "groupLimits": [{"groupIds": ["new-group"], "maxCount": 7}]}]}]}
        info = {"width": 2, "height": 2, "fileSize": 100}
        self.assertEqual(asc.match_spec(info, ref), {"group": "new-group", "specId": "dynamic-spec", "limit": 7})
        with self.assertRaises(ValueError):
            asc.match_spec(dict(info, width=3), ref)

    def test_existing_asset_and_ambiguous_match(self):
        image = {"locale": "ja", "sha256": "hash", "fileName": "home.png", "fileSize": 100, "specId": "spec"}
        asset = {"id": "existing", "attributes": {"fileName": "home.png", "fileSize": 100, "specId": "spec"}}
        self.assertEqual(asc.find_image(image, [asset]), asset)
        self.assertIsNone(asc.find_image(dict(image, fileSize=101), [asset]))
        with self.assertRaises(ValueError):
            asc.find_image(image, [asset, asset])

    def test_upload_has_no_jwt_and_checks_ranges_and_hosts(self):
        c = client()
        c.opener = FakeOpener([{}])
        op = {"url": "https://store-030.blobstore.apple.com/path?secret=hidden", "method": "PUT", "offset": 0, "length": 4,
            "requestHeaders": [{"name": "Content-Type", "value": "image/png"}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"image.png"
            path.write_bytes(b"test")
            asc.upload_parts(c, {"attributes": {"uploadOperations": [op]}}, path)
            self.assertNotIn("Authorization", c.opener.requests[0].headers)
            self.assertEqual(c.opener.requests[0].data, b"test")
            c.opener = FakeOpener([{}])
            asc.upload_parts(c, {"attributes": {"uploadOperations": [dict(op,
                url="https://northamerica-1.object-storage.apple.com/path?signed=hidden")]}}, path)
            self.assertNotIn("Authorization", c.opener.requests[0].headers)
            for bad in (dict(op, url="https://northamerica-1.object-storage.apple.com.evil.example/path"), dict(op, url="https://evil.example/path"), dict(op, offset=1), dict(op, length=3)):
                with self.assertRaises(ValueError):
                    asc.upload_parts(c, {"attributes": {"uploadOperations": [bad]}}, path)



class ReleaseTests(unittest.TestCase):
    def test_distribution_profile_rejects_wrong_bundle_cert_and_debug(self):
        import release_appstore as release
        from datetime import datetime, timedelta, timezone
        profile = {'TeamIdentifier': [release.TEAM],
            'Entitlements': {'application-identifier': release.TEAM+'.'+release.BUNDLES[0],
                             'keychain-access-groups': [release.TEAM+'.*'], 'get-task-allow': False},
            'ExpirationDate': datetime.now(timezone.utc)+timedelta(days=1), 'DeveloperCertificates': [b'cert']}
        release.validate_profile(profile, release.BUNDLES[0], b'cert')
        for bundle, cert in ((release.BUNDLES[1], b'cert'), (release.BUNDLES[0], b'other')):
            with self.assertRaises(ValueError):
                release.validate_profile(profile, bundle, cert)
        profile['Entitlements']['get-task-allow'] = True
        with self.assertRaises(ValueError):
            release.validate_profile(profile, release.BUNDLES[0], b'cert')

    def test_prepare_existing_items_is_idempotent_and_never_submits(self):
        import release_appstore as release
        from unittest.mock import Mock
        c = Mock()
        build = {'id': 'build', 'attributes': {'processingState': 'VALID', 'expired': False, 'usesNonExemptEncryption': False}}
        draft = {'id': 'draft', 'attributes': {'platform': 'IOS', 'state': 'READY_FOR_REVIEW', 'submittedDate': None}}
        items = [
            {'attributes': {'state': 'READY_FOR_REVIEW'}, 'relationships': {'appStoreVersion': asc.relationship('appStoreVersions', 'version'), 'inAppPurchaseVersion': {'data': None}}},
            {'attributes': {'state': 'READY_FOR_REVIEW'}, 'relationships': {'appStoreVersion': {'data': None}, 'inAppPurchaseVersion': asc.relationship('inAppPurchaseVersions', 'iap-version')}}]
        def listing(path, params=None):
            if path == 'reviewSubmissions':
                return [draft]
            if path.endswith('/versions'):
                return [{'id': 'iap-version', 'attributes': {'state': 'PREPARE_FOR_SUBMISSION'}}]
            return items
        c.list.side_effect = listing
        c.request.side_effect = lambda method, path: {'data': draft if path == 'reviewSubmissions/draft' else {'id': 'build'}}
        with tempfile.TemporaryDirectory() as tmp, patch.object(release, 'matching_builds', return_value=[build]), patch.object(asc, 'target', return_value=({}, {'id': 'version'}, [])):
            result = release.prepare(c, Path(tmp), [{'CFBundleShortVersionString': '1.7.1', 'CFBundleVersion': '9'}])
        self.assertFalse(result['submitted'])
        self.assertTrue(all(call.args[0] == 'GET' for call in c.request.call_args_list))

    def test_review_screenshot_reuses_processed_source_name(self):
        import hashlib
        import release_appstore as release
        from types import SimpleNamespace
        from unittest.mock import Mock
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'pro.png'
            path.write_bytes(png())
            attrs = {'fileName': 'SOURCE', 'fileSize': path.stat().st_size,
                'sourceFileChecksum': hashlib.md5(path.read_bytes()).hexdigest(),
                'assetDeliveryState': {'state': 'COMPLETE'}, 'imageAsset': {'width': 2, 'height': 2}}
            c = Mock(allow_v2=True, release_setup=True)
            c.request.return_value = {'data': {'id': 'existing', 'attributes': attrs}}
            result = release.execute(SimpleNamespace(action='review-screenshot', screenshot=path), c)
            self.assertEqual(result['state'], 'COMPLETE')
            self.assertTrue(all(call.args[0] == 'GET' for call in c.request.call_args_list))

    def test_local_signing_files_are_private(self):
        import release_appstore as release
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'state.json'
            path.write_text('old')
            path.chmod(0o644)
            release.private_write(path, b'new')
            self.assertEqual(path.read_bytes(), b'new')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

if __name__ == "__main__":
    unittest.main()
