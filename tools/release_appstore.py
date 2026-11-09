"""Texel's local manual-signing release workflow; never submits or publishes."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import secrets
import signal
import subprocess
import tempfile
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
import appstoreconnect as asc

TEAM = 'R9UJHHAZQ4'
BUNDLES = ('com.lingxifox.Texel', 'com.lingxifox.Texel.Share')
SIGNING = Path.home()/'.config/appstoreconnect/signing'


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'wb') as f:
        os.fchmod(f.fileno(), 0o600)
        f.write(data)


def run(cmd, log, client):
    """Keep command arguments and secret-bearing tool diagnostics out of chat."""
    with os.fdopen(os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            for line in process.stdout:
                for secret in client.secrets:
                    line = line.replace(secret, '[REDACTED]')
                f.write(asc.redact(line))
                f.flush()
            code = process.wait()
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    if code:
        raise ValueError(f'Tool failed ({code}); inspect sanitized log: {log}')


def validate_profile(profile, bundle, certificate):
    ent = profile['Entitlements']
    if (profile['TeamIdentifier'] != [TEAM]
            or ent.get('application-identifier') != TEAM+'.'+bundle
            or ent.get('get-task-allow', False)
            or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')
            or profile['ExpirationDate'].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)
            or certificate not in profile['DeveloperCertificates']):
        raise ValueError('App Store profile, team, certificate, expiry or bundle mismatch.')
    groups = ent.get('keychain-access-groups', [])
    wanted = TEAM+'.com.lingxifox.Texel.shared'
    if wanted not in groups and TEAM+'.*' not in groups:
        raise ValueError('Profile does not permit the shared Keychain group.')


def signing(client):
    """Reuse the already authorized local certificate; create only missing profiles."""
    meta = json.loads((SIGNING/'Texel-Distribution.json').read_text())
    cert_bytes = (SIGNING/'Texel-Distribution.cer').read_bytes()
    cert = x509.load_der_x509_certificate(cert_bytes)
    key = serialization.load_pem_private_key((SIGNING/'Texel-Distribution.key').read_bytes(), None)
    pub = lambda k: k.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    if pub(key.public_key()) != pub(cert.public_key()) or cert.not_valid_after_utc <= datetime.now(timezone.utc):
        raise ValueError('Local certificate/key mismatch or expired certificate.')
    if cert.subject.get_attributes_for_oid(x509.NameOID.ORGANIZATIONAL_UNIT_NAME)[0].value != TEAM:
        raise ValueError('Certificate belongs to another team.')
    remote = client.request('GET', 'certificates/'+meta['certificate_id'])['data']
    if base64.b64decode(remote['attributes']['certificateContent']) != cert_bytes:
        raise ValueError('Local certificate does not match Apple certificate record.')
    fingerprint = cert.fingerprint(hashes.SHA1()).hex().upper()
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    if fingerprint not in identities:
        # A transient password-protected container stays in the restricted local directory.
        fd, path = tempfile.mkstemp(suffix='.p12', dir=SIGNING)
        password = secrets.token_urlsafe(32)
        client.secrets.append(password)
        try:
            os.close(fd)
            # Apple's importer requires the native PKCS#12 encoding.
            subprocess.run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(SIGNING/'Texel-Distribution.key'),
                            '-in', '/dev/stdin', '-out', path, '-passout', 'pass:'+password, '-name', 'Texel Distribution'],
                           input=cert.public_bytes(serialization.Encoding.PEM), check=True, capture_output=True)
            result = subprocess.run(['security', 'import', path, '-k', str(Path.home()/'Library/Keychains/login.keychain-db'),
                                     '-P', password, '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'], capture_output=True)
            if result.returncode:
                raise ValueError('Keychain import failed: '+result.stderr.decode(errors='replace').strip())
        finally:
            Path(path).unlink(missing_ok=True)
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    if fingerprint not in identities:
        raise ValueError('Imported certificate is not a valid signing identity.')
    results = []
    profiles = client.list('profiles', {'filter[profileType]': 'IOS_APP_STORE', 'limit': 200})
    for bundle in BUNDLES:
        ids = [item for item in client.list('bundleIds', {'filter[identifier]': bundle})
               if item['attributes']['identifier'] == bundle]
        if len(ids) != 1 or ids[0]['attributes']['seedId'] != TEAM:
            raise ValueError('Bundle registration/team mismatch.')
        matches = []
        for p in profiles:
            if p['attributes']['profileState'] != 'ACTIVE':
                continue
            decoded = plistlib.loads(subprocess.check_output(['security', 'cms', '-D'], input=base64.b64decode(p['attributes']['profileContent']), stderr=subprocess.DEVNULL))
            try:
                validate_profile(decoded, bundle, cert_bytes)
            except ValueError:
                continue
            matches.append((p, decoded))
        if matches:
            p, decoded = max(matches, key=lambda pair: pair[1]['ExpirationDate'])
        else:
            p = client.request('POST', 'profiles', asc.resource('profiles',
                {'name': 'Texel App Store '+bundle+' '+meta['certificate_id'], 'profileType': 'IOS_APP_STORE'},
                relationships={'bundleId': asc.relationship('bundleIds', ids[0]['id']),
                               'certificates': {'data': [{'type': 'certificates', 'id': meta['certificate_id']}]}}))['data']
            decoded = plistlib.loads(subprocess.check_output(['security', 'cms', '-D'], input=base64.b64decode(p['attributes']['profileContent']), stderr=subprocess.DEVNULL))
            validate_profile(decoded, bundle, cert_bytes)
        profile_path = Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'/ (decoded['UUID']+'.mobileprovision')
        private_write(profile_path, base64.b64decode(p['attributes']['profileContent']))
        results.append({'bundle': bundle, 'id': p['id'], 'uuid': decoded['UUID'], 'name': decoded['Name'],
                        'expires': decoded['ExpirationDate'].isoformat()+'Z'})
    config = f'TEXEL_APP_STORE_PROFILE = {results[0]["uuid"]}\nTEXEL_SHARE_APP_STORE_PROFILE = {results[1]["uuid"]}\n'
    private_write(SIGNING/'Texel-Release.xcconfig', config.encode())
    state = {'certificate_id': meta['certificate_id'], 'fingerprint': fingerprint,
             'certificate_expires': cert.not_valid_after_utc.isoformat(), 'profiles': results}
    private_write(SIGNING/'release-state.json', asc.dump(state).encode())
    return state


def validate_archive(archive, state, version="1.7.1"):
    app = archive/'Products/Applications/LingXiStyle.app'
    results = []
    for bundle, path in zip(BUNDLES, (app, app/'PlugIns/LingXiStyleShare.appex')):
        info = plistlib.loads((path/'Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != bundle or info['CFBundleShortVersionString'] != version:
            raise ValueError('Archived bundle or version mismatch.')
        # shortcut: pin the validated stable SDK; update this check when upgrading Xcode.
        if not info['DTSDKName'].startswith('iphoneos27.2'):
            raise ValueError('Expected the selected stable iPhoneOS 27.2 SDK.')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True, capture_output=True)
        signature = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], check=True, capture_output=True, text=True).stderr
        if 'TeamIdentifier='+TEAM not in signature or 'Authority=Apple Distribution:' not in signature:
            raise ValueError('Archived code is not signed by the expected distribution team.')
        ent = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(path)], stderr=subprocess.DEVNULL))
        if ent.get('get-task-allow', False) or ent.get('keychain-access-groups') != [TEAM+'.com.lingxifox.Texel.shared']:
            raise ValueError('Archived Keychain entitlement or distribution signing mismatch.')
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path/'embedded.mobileprovision')], stderr=subprocess.DEVNULL))
        validate_profile(profile, bundle, (SIGNING/'Texel-Distribution.cer').read_bytes())
        results.append({k: info[k] for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'DTSDKName')})
    if (app/'PlugIns/LingXiStyleShare.appex/Frameworks').exists():
        raise ValueError('Extensions must load shared frameworks from the containing app.')
    if results[0]['CFBundleVersion'] != results[1]['CFBundleVersion'] or list(app.rglob('*.storekit')):
        raise ValueError('Build numbers differ or local StoreKit configuration is embedded.')
    return results



def matching_builds(client, version, number):
    builds = client.list('builds', {'filter[app]': asc.APP_ID, 'filter[version]': number})
    return [b for b in builds if client.request('GET', 'builds/'+b['id']+'/preReleaseVersion')['data']['attributes']['version'] == version]


def prepare(client, output, verified):
    deadline = time.monotonic()+1800
    while True:
        builds = matching_builds(client, verified[0]['CFBundleShortVersionString'], verified[0]['CFBundleVersion'])
        if len(builds) > 1:
            raise ValueError('Ambiguous build records.')
        build = builds[0] if builds else None
        state = build['attributes']['processingState'] if build else 'NOT_VISIBLE'
        private_write(output/'processing.json', asc.dump({'state': state, 'build_id': build['id'] if build else None}).encode())
        if state == 'VALID':
            break
        if state in {'FAILED', 'INVALID'} or time.monotonic() >= deadline:
            raise ValueError('Apple build processing: '+state)
        time.sleep(60)
    if build['attributes'].get('expired'):
        raise ValueError('Apple build has expired.')
    if build['attributes'].get('usesNonExemptEncryption') is not False:
        client.request('PATCH', 'builds/'+build['id'], asc.resource('builds', {'usesNonExemptEncryption': False}, build['id']))
    _, version, _ = asc.target(client, asc.APP_ID, verified[0]['CFBundleShortVersionString'])
    endpoint = 'appStoreVersions/'+version['id']+'/relationships/build'
    linked = client.request('GET', endpoint)['data']
    if not linked or linked['id'] != build['id']:
        client.request('PATCH', endpoint, asc.relationship('builds', build['id']))
    if client.request('GET', endpoint)['data']['id'] != build['id']:
        raise ValueError('Build attachment readback mismatch.')
    drafts = [d for d in client.list('reviewSubmissions', {'filter[app]': asc.APP_ID})
              if d['attributes']['platform'] == 'IOS' and d['attributes']['submittedDate'] is None]
    if len(drafts) > 1:
        raise ValueError('Multiple review drafts; do not create a duplicate.')
    draft = drafts[0] if drafts else client.request('POST', 'reviewSubmissions', asc.resource(
        'reviewSubmissions', {'platform': 'IOS'}, relationships={'app': asc.relationship('apps', asc.APP_ID)}))['data']
    if draft['attributes']['state'] != 'READY_FOR_REVIEW':
        raise ValueError('Existing draft is not editable.')
    items_path = 'reviewSubmissions/'+draft['id']+'/items'
    item_params = {'include': 'appStoreVersion,inAppPurchaseVersion'}
    items = client.list(items_path, item_params)
    iap_versions = client.list('/v2/inAppPurchases/6832499022/versions')
    editable = [v for v in iap_versions if v['attributes']['state'] in {'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', 'READY_TO_SUBMIT'}]
    if len(editable) != 1:
        raise ValueError('Expected exactly one editable IAP version.')
    for relation, kind, identifier in [('appStoreVersion', 'appStoreVersions', version['id']),
            ('inAppPurchaseVersion', 'inAppPurchaseVersions', editable[0]['id'])]:
        if not any(item.get('relationships', {}).get(relation, {}).get('data') and item['relationships'][relation]['data'].get('id') == identifier for item in items):
            item = client.request('POST', 'reviewSubmissionItems', asc.resource('reviewSubmissionItems', {}, relationships={
                'reviewSubmission': asc.relationship('reviewSubmissions', draft['id']), relation: asc.relationship(kind, identifier)}))['data']
            items.append(item)
    draft = client.request('GET', 'reviewSubmissions/'+draft['id'])['data']
    if draft['attributes']['submittedDate'] is not None:
        raise ValueError('Unexpected submitted draft; no further action taken.')
    final_items = client.list(items_path, item_params)
    if any(item['attributes']['state'] != 'READY_FOR_REVIEW' for item in final_items):
        raise ValueError('A review draft item is not ready; inspect the existing draft.')
    result = {'build_id': build['id'], 'build_processing': state, 'app_version_id': version['id'],
              'draft_id': draft['id'], 'draft_state': draft['attributes']['state'], 'submitted': False,
              'items': final_items}
    private_write(output/'ready-for-user-review.json', asc.dump(result).encode())
    return result

def execute(args, client):
    if args.action == 'signing':
        if not client.signing_setup:
            raise ValueError('Local signing setup requires --signing-setup.')
        return signing(client)
    if args.action in {'review-screenshot', 'prepare'} and not (client.allow_v2 and client.release_setup):
        raise ValueError('Review preparation requires --allow-v2 --release-setup; it never submits.')
    if args.action == 'review-screenshot':
        if not args.screenshot:
            raise ValueError('--screenshot must name the reviewed real Pro screen capture.')
        path = args.screenshot.resolve()
        info = asc.png_info(path)
        checksum = hashlib.md5(path.read_bytes()).hexdigest()
        current = asc.optional(client, 'https://api.appstoreconnect.apple.com/v2/inAppPurchases/6832499022/appStoreReviewScreenshot')
        if current:
            actual = current['attributes']
            same_source = actual.get('sourceFileChecksum') == checksum if actual.get('sourceFileChecksum') else actual['fileName'] == path.name
            if actual['fileSize'] != info['fileSize'] or not same_source:
                raise ValueError('A different review screenshot exists; replacement/deletion requires separate approval.')
        if not current:
            current = client.request('POST', 'inAppPurchaseAppStoreReviewScreenshots', asc.resource(
                'inAppPurchaseAppStoreReviewScreenshots', {'fileName': path.name, 'fileSize': info['fileSize']},
                relationships={'inAppPurchaseV2': asc.relationship('inAppPurchases', '6832499022')}))['data']
        endpoint = 'inAppPurchaseAppStoreReviewScreenshots/'+current['id']
        state = current['attributes']['assetDeliveryState']['state']
        if state == 'AWAITING_UPLOAD':
            asc.upload_parts(client, current, path)
            client.request('PATCH', endpoint, asc.resource('inAppPurchaseAppStoreReviewScreenshots',
                {'sourceFileChecksum': checksum, 'uploaded': True}, current['id']))
        deadline = time.monotonic()+600
        while True:
            current = client.request('GET', endpoint)['data']
            state = current['attributes']['assetDeliveryState']['state']
            if state in {'COMPLETE', 'FAILED'} or time.monotonic() >= deadline:
                break
            time.sleep(15)
        dimensions = current['attributes'].get('imageAsset') or {}
        if state != 'COMPLETE' or current['attributes']['sourceFileChecksum'] != checksum or (dimensions.get('width'), dimensions.get('height')) != (info['width'], info['height']):
            raise ValueError('Apple review screenshot not verified: '+state)
        return {'id': current['id'], 'state': state, 'sha256': info['sha256'], 'width': info['width'], 'height': info['height']}
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    state = json.loads((SIGNING/'release-state.json').read_text())
    archive = output/'Texel.xcarchive'
    if args.action == 'archive':
        if archive.exists():
            raise ValueError('Archive already exists; choose a new output directory.')
        version = subprocess.check_output(['xcodebuild', '-version'], text=True)
        if version.splitlines()[0] != 'Xcode 27.2':
            raise ValueError('Select the installed stable Xcode 27.2 before building.')
        run(['xcodegen', 'generate'], output/'generate.log', client)
        run(['xcodebuild', '-project', 'LingXiStyle.xcodeproj', '-scheme', 'LingXiStyle', '-configuration', 'Release',
             '-destination', 'generic/platform=iOS', '-xcconfig', str(SIGNING/'Texel-Release.xcconfig'),
             '-derivedDataPath', str(output/'DerivedData'), '-archivePath', str(archive), 'archive'], output/'archive.log', client)
        result = validate_archive(archive, state, args.version)
        asc.save(output/'archive-verified.json', result)
        return result
    verified = validate_archive(archive, state, args.version)
    if args.action == 'prepare':
        return prepare(client, output, verified)
    existing = matching_builds(client, verified[0]['CFBundleShortVersionString'], verified[0]['CFBundleVersion'])
    if existing:
        return {'upload_skipped_existing_build': [{'id': b['id'], 'attributes': b['attributes']} for b in existing]}
    options = {'method': 'app-store-connect', 'destination': 'upload', 'signingStyle': 'manual', 'teamID': TEAM,
               'signingCertificate': state['fingerprint'], 'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True,
               'provisioningProfiles': {p['bundle']: p['uuid'] for p in state['profiles']}}
    private_write(output/'UploadOptions.plist', plistlib.dumps(options))
    config = json.loads((Path.home()/'.config/appstoreconnect/config.json').read_text())
    values = {k: os.environ.get(k) or config[k] for k in ('ASC_PRIVATE_KEY_PATH', 'ASC_KEY_ID', 'ASC_ISSUER_ID')}
    run(['xcodebuild', '-exportArchive', '-archivePath', str(archive), '-exportPath', str(output/'Upload'),
         '-exportOptionsPlist', str(output/'UploadOptions.plist'), '-authenticationKeyPath', str(Path(values['ASC_PRIVATE_KEY_PATH']).expanduser()),
         '-authenticationKeyID', values['ASC_KEY_ID'], '-authenticationKeyIssuerID', values['ASC_ISSUER_ID']], output/'upload.log', client)
    return {'uploaded': True, 'archive': str(archive), 'processing': 'Check ASC builds before linking to the store version.'}


def add_parser(sub):
    parser = sub.add_parser('release', help='Local manual signing, stable archive and upload; never submits.')
    parser.add_argument('action', choices=['signing', 'archive', 'upload', 'review-screenshot', 'prepare'])
    parser.add_argument('--screenshot', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.tmp/appstoreconnect/manual-release'))
