"""Texel signing, markets and approved creatives; never submits or releases App versions."""
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
    if version.get('attributes', {}).get('appStoreState') == 'READY_FOR_SALE':
        if not linked or linked['id'] != build['id']:
            raise ValueError('Published version uses a different build; no review draft was created.')
        return {'build_id': build['id'], 'build_processing': state, 'already_released': True, 'submitted': False}
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
    if args.action == 'availability':
        return availability(args, client)
    if args.action == 'creative':
        return creative(args, client)
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
    parser = sub.add_parser('release', help='Local signing, market preparation and creative assets; never submits App versions.')
    parser.add_argument('action', choices=['signing', 'archive', 'upload', 'review-screenshot', 'prepare', 'availability', 'creative'])
    parser.add_argument('--apply-plan', type=Path)
    parser.add_argument('--image', type=Path)
    parser.add_argument('--submit-asset-review', action='store_true')
    parser.add_argument('--publish-approved', action='store_true')
    parser.add_argument('--watch-approval', action='store_true')
    parser.add_argument('--screenshot', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.tmp/appstoreconnect/manual-release'))


def market_snapshot(client):
    territories = client.list('territories', {'limit': 200})
    app = client.request('GET', f'apps/{asc.APP_ID}/appAvailabilityV2')['data']
    rows = client.list(f'/v2/appAvailabilities/{app["id"]}/territoryAvailabilities', {'include': 'territory', 'limit': 200})
    iap = client.request('GET', '/v2/inAppPurchases/6832499022/inAppPurchaseAvailability')['data']
    enabled = client.list(f'inAppPurchaseAvailabilities/{iap["id"]}/availableTerritories', {'limit': 200})
    base = client.request('GET', 'inAppPurchasePriceSchedules/6832499022/baseTerritory')['data']['id']
    manual = client.request('GET', 'inAppPurchasePriceSchedules/6832499022/manualPrices',
                            params={'include': 'inAppPurchasePricePoint,territory', 'limit': 200})
    points = [p for p in manual.get('included', []) if p['type'] == 'inAppPurchasePricePoints']
    if base != 'USA' or len(manual['data']) != 1 or not any(p['attributes']['customerPrice'] == '2.99' for p in points):
        raise ValueError('Expected the unchanged USA $2.99 base price; no price write is permitted.')
    return {'territories': sorted(t['id'] for t in territories), 'app_id': app['id'],
            'app_new_territories': app['attributes']['availableInNewTerritories'],
            'iap_new_territories': iap['attributes']['availableInNewTerritories'],
            'app_rows': rows, 'iap_available': sorted(t['id'] for t in enabled),
            'prices': {'base': base, 'manual': manual['data'], 'points': points}}


def market_plan(snapshot):
    wanted = sorted(t for t in snapshot['territories'] if t != 'CHN')
    if 'CHN' not in snapshot['territories'] or 'USA' not in wanted:
        raise ValueError('Unexpected Apple territory inventory.')
    app = {r['relationships']['territory']['data']['id']: r['attributes']['available'] for r in snapshot['app_rows']}
    if set(app) != set(snapshot['territories']):
        raise ValueError('Incomplete app territory inventory; refusing a partial plan.')
    if snapshot['app_new_territories'] or snapshot['iap_new_territories']:
        raise ValueError('Disable automatic future territories before applying this workflow.')
    current = sorted(t for t, available in app.items() if available)
    return {'app_id': asc.APP_ID, 'product_id': asc.PRODUCT_ID, 'excluded': ['CHN'],
            'territories': snapshot['territories'], 'desired': wanted, 'future_territories': False,
            'before': {'app': current, 'iap': snapshot['iap_available']},
            'add': {'app': sorted(set(wanted)-set(current)), 'iap': sorted(set(wanted)-set(snapshot['iap_available']))},
            'remove': {'app': sorted(set(current)-set(wanted)), 'iap': sorted(set(snapshot['iap_available'])-set(wanted))},
            'prices': snapshot['prices']}


def availability(args, client):
    if not (client.allow_v2 and client.release_setup):
        raise ValueError('Market preparation requires --allow-v2 --release-setup.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    current = market_snapshot(client)
    if not args.apply_plan:
        plan = market_plan(current)
        asc.save(output/'availability-plan.json', plan)
        return plan
    plan = json.loads(args.apply_plan.read_text())
    expected = sorted(t for t in current['territories'] if t != 'CHN')
    if (plan['app_id'] != asc.APP_ID or plan['product_id'] != asc.PRODUCT_ID or plan['desired'] != expected
            or plan['excluded'] != ['CHN'] or plan['future_territories'] is not False
            or current['prices'] != plan['prices'] or current['app_new_territories'] or current['iap_new_territories']):
        raise ValueError('Availability preview, price or future-territory settings changed.')
    if current['iap_available'] not in [plan['before']['iap'], expected]:
        raise ValueError('IAP territory selection changed since preview.')
    asc.save(output/f'availability-before-{int(time.time())}.json', current)
    if current['iap_available'] != expected:
        client.request('POST', 'inAppPurchaseAvailabilities', asc.resource('inAppPurchaseAvailabilities',
            {'availableInNewTerritories': False}, relationships={
                'inAppPurchase': asc.relationship('inAppPurchases', '6832499022'),
                'availableTerritories': {'data': [{'type': 'territories', 'id': t} for t in expected]}}))
        readback = client.list('inAppPurchaseAvailabilities/6832499022/availableTerritories', {'limit': 200})
        if sorted(t['id'] for t in readback) != expected:
            raise ValueError('IAP territory readback mismatch; App territories remain unchanged.')
    changed = []
    for row in current['app_rows']:
        territory = row['relationships']['territory']['data']['id']
        wanted = territory != 'CHN'
        if row['attributes']['available'] != wanted:
            response = client.request('PATCH', 'territoryAvailabilities/'+row['id'],
                asc.resource('territoryAvailabilities', {'available': wanted}, row['id']))['data']
            if response['attributes']['available'] != wanted:
                raise ValueError('App territory response mismatch: '+territory)
            changed.append(territory)
            private_write(output/'availability-progress.json', asc.dump({'changed': changed}).encode())
    after = market_snapshot(client)
    available = sorted(r['relationships']['territory']['data']['id'] for r in after['app_rows'] if r['attributes']['available'])
    if available != expected or after['iap_available'] != expected or after['prices'] != plan['prices']:
        raise ValueError('Final availability or price readback mismatch.')
    private_write(output/'availability-verified.json', asc.dump(after).encode())
    return {'configured': len(expected), 'excluded': ['CHN'], 'future_territories': False,
            'app_changed': changed, 'iap_matches_app': True,
            'territory_states': {r['relationships']['territory']['data']['id']: r['attributes']['contentStatuses'] for r in after['app_rows']}}


def creative(args, client):
    if not args.image:
        raise ValueError('--image must name the approved search-results creative.')
    image = asc.png_info(args.image.resolve())
    refdata = client.request('GET', 'appAssetLibraryRefData')['data'][0]['attributes']
    placement_type = 'APP_STORE_SEARCH_RESULTS_ASSET'
    mapping = next(p for p in refdata['placementTypes'] if p['placementTypeId'] == placement_type)
    specs = [s for s in refdata['imageSpecs'] if s['specId'] in mapping['specMappings'][0]['specs']]
    matches = [s for s in specs if s['dimensions']['minWidth'] <= image['width'] <= s['dimensions']['maxWidth']
               and s['dimensions']['minHeight'] <= image['height'] <= s['dimensions']['maxHeight']
               and (s.get('aspectRatio') != '3:2' or image['width']*2 == image['height']*3)]
    if len(matches) != 1:
        raise ValueError('Creative dimensions do not match exactly one live Apple image specification.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app, version, _ = asc.target(client, asc.APP_ID, args.version)
    if app['attributes']['bundleId'] != BUNDLES[0]:
        raise ValueError('Unexpected app identity.')
    library = client.request('GET', f'apps/{asc.APP_ID}/assetLibrary')['data']
    assets = client.list(f'appAssetLibraries/{library["id"]}/images')
    reference = 'texel-search-'+image['sha256']
    candidates = [a for a in assets if a['attributes'].get('referenceName') == reference]
    if len(candidates) > 1:
        raise ValueError('Duplicate creative reservations; no resources were modified.')
    asset = candidates[0] if candidates else client.request('POST', 'appAssetLibraryImages', asc.resource(
        'appAssetLibraryImages', {'fileName': image['fileName'], 'fileSize': image['fileSize'],
            'category': 'CREATIVE_ASSETS', 'referenceName': reference},
        relationships={'assetLibrary': asc.relationship('appAssetLibraries', library['id'])}))['data']
    endpoint = 'appAssetLibraryImages/'+asset['id']
    asset = client.request('GET', endpoint)['data']
    if asset['attributes']['state'] == 'AWAITING_UPLOAD':
        asc.upload_parts(client, asset, args.image)
        client.request('PATCH', endpoint, asc.resource('appAssetLibraryImages', {'uploaded': True}, asset['id']))
    deadline = time.monotonic()+600
    while True:
        asset = client.request('GET', endpoint)['data']
        state = asset['attributes']['state']
        if state != 'UPLOAD_COMPLETE' or time.monotonic() >= deadline:
            break
        time.sleep(15)
    if state in {'FAILED', 'REJECTED', 'ARCHIVED', 'AWAITING_UPLOAD', 'UPLOAD_COMPLETE'}:
        raise ValueError('Creative asset not ready: '+state)
    dimensions = asset['attributes'].get('imageAsset') or {}
    if asset['attributes']['specId'] != matches[0]['specId'] or (dimensions.get('width'), dimensions.get('height')) != (image['width'], image['height']):
        raise ValueError('Apple processed creative dimensions/specification mismatch.')
    review = None
    if args.submit_asset_review and state in {'PREPARE_FOR_SUBMISSION', 'COMPLETE', 'READY_FOR_REVIEW'}:
        if not client.release_setup:
            raise ValueError('--release-setup is required for the separately authorized creative review.')
        drafts = [d for d in client.list('reviewSubmissions', {'filter[app]': asc.APP_ID})
                  if d['attributes']['state'] == 'READY_FOR_REVIEW' and not d['attributes'].get('submittedDate')]
        candidates = []
        for draft in drafts:
            items = client.list('reviewSubmissions/'+draft['id']+'/items', {'include': 'appAssetLibraryImage,appStoreVersion,inAppPurchaseVersion'})
            if items and all((i.get('relationships', {}).get('appAssetLibraryImage', {}).get('data') or {}).get('id') == asset['id'] for i in items):
                candidates.append(draft)
        if len(candidates) > 1:
            raise ValueError('Multiple creative review drafts; no duplicate will be created.')
        if candidates:
            review = candidates[0]
        else:
            review = client.request('POST', 'reviewSubmissions', asc.resource('reviewSubmissions', {'platform': 'IOS'},
                relationships={'app': asc.relationship('apps', asc.APP_ID)}))['data']
            client.request('POST', 'reviewSubmissionItems', asc.resource('reviewSubmissionItems', {}, relationships={
                'reviewSubmission': asc.relationship('reviewSubmissions', review['id']),
                'appAssetLibraryImage': asc.relationship('appAssetLibraryImages', asset['id'])}))
        client.creative_review_image = asset['id']
        client.request('PATCH', 'reviewSubmissions/'+review['id'], asc.resource('reviewSubmissions', {'submitted': True}, review['id']))
        review = client.request('GET', 'reviewSubmissions/'+review['id'])['data']
        asset = client.request('GET', endpoint)['data']
        state = asset['attributes']['state']
    if args.watch_approval and state != 'APPROVED':
        deadline = time.monotonic()+86400
        while state != 'APPROVED':
            private_write(output/'creative-state.json', asc.dump({'asset_id': asset['id'], 'state': state, 'publish_deferred': True}).encode())
            if state in {'FAILED', 'REJECTED', 'ARCHIVED'} or time.monotonic() >= deadline:
                raise ValueError('Creative approval watcher stopped: '+state)
            time.sleep(60)
            asset = client.request('GET', endpoint)['data']
            state = asset['attributes']['state']
    placements = []
    if args.publish_approved and state == 'APPROVED':
        live = client.request('GET', 'appStoreVersions/'+version['id'])['data']
        if live['attributes']['appStoreState'] != 'READY_FOR_SALE':
            raise ValueError('The reviewed App version is no longer live; automatic placement stopped.')
        for locale in client.list('appStoreVersions/'+version['id']+'/appStoreVersionLocalizations'):
            existing = client.list('appStoreVersionLocalizations/'+locale['id']+'/placements', {'include': 'image'})
            relevant = [p for p in existing if p['attributes']['placementType'] == placement_type]
            if relevant:
                if len(relevant) != 1 or relevant[0]['relationships']['image']['data']['id'] != asset['id']:
                    raise ValueError('A different search creative exists; no replacement/deletion is authorized.')
                placement = relevant[0]
            else:
                placement = client.request('POST', 'appAssetLibraryPlacements', asc.resource('appAssetLibraryPlacements',
                    {'placementType': placement_type, 'placementGroup': mapping['specMappings'][0]['placementGroupId']}, relationships={
                        'image': asc.relationship('appAssetLibraryImages', asset['id']),
                        'appStoreVersionLocalization': asc.relationship('appStoreVersionLocalizations', locale['id'])}))['data']
            readback = client.request('GET', 'appAssetLibraryPlacements/'+placement['id'])['data']
            if readback['attributes']['state'] not in {'ACTIVE', 'PARENT_APPROVED'}:
                raise ValueError('Search creative placement is not active: '+readback['attributes']['state'])
            placements.append({'locale': locale['attributes']['locale'], 'id': placement['id'], 'state': readback['attributes']['state']})
    result = {'asset_id': asset['id'], 'state': state, 'image': image,
              'review': {'id': review['id'], 'state': review['attributes']['state'], 'submittedDate': review['attributes'].get('submittedDate')} if review else None,
              'placements': placements, 'publish_deferred': bool(args.publish_approved and state != 'APPROVED')}
    private_write(output/'creative-state.json', asc.dump(result).encode())
    return result
