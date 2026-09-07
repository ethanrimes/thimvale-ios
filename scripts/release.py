#!/usr/bin/env python3
"""Sign and upload on a disposable GitHub-hosted Mac; never prints secrets."""
import base64
import datetime as dt
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import sys
import tempfile
import uuid

BUNDLE_ID = "com.ethanrimes.thimvale"  # Must match the registered App Store Connect app.
REQUIRED = (
    "APPLE_TEAM_ID", "IOS_DISTRIBUTION_P12_BASE64", "IOS_DISTRIBUTION_P12_PASSWORD",
    "IOS_PROVISIONING_PROFILE_BASE64", "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY",
)


def preflight(env):
    missing = [key for key in REQUIRED if not env.get(key, "").strip()]
    if missing:
        raise ValueError("Missing GitHub configuration: " + ", ".join(missing))
    for key in ("APPLE_TEAM_ID", "APP_STORE_CONNECT_KEY_ID"):
        if not re.fullmatch(r"[A-Z0-9]{10}", env[key]):
            raise ValueError(f"{key} must be a 10-character Apple identifier.")
    try:
        uuid.UUID(env["APP_STORE_CONNECT_ISSUER_ID"])
    except ValueError:
        raise ValueError("APP_STORE_CONNECT_ISSUER_ID must be the team key's Issuer ID.") from None
    if "-----BEGIN PRIVATE KEY-----" not in env["APP_STORE_CONNECT_PRIVATE_KEY"]:
        raise ValueError("APP_STORE_CONNECT_PRIVATE_KEY must contain the .p8 file, not its path or Base64.")
    for key in ("IOS_DISTRIBUTION_P12_BASE64", "IOS_PROVISIONING_PROFILE_BASE64"):
        decode_secret(env[key], key)


def decode_secret(value, name):
    try:
        result = base64.b64decode("".join(value.split()), validate=True)
    except (ValueError, base64.binascii.Error):
        raise ValueError(f"{name} must be Base64-encoded file contents.") from None
    if not result:
        raise ValueError(f"{name} is empty.")
    return result


def validate_profile(profile, team, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        raise ValueError("Provisioning profile has no expiration date.")
    if expiration.replace(tzinfo=dt.timezone.utc) <= now:
        raise ValueError("Provisioning profile has expired. Regenerate it in Apple Developer.")
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Provisioning profile belongs to a different Apple team.")
    entitlement = profile.get("Entitlements", {})
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    expected_ids = [prefix + "." + BUNDLE_ID for prefix in prefixes]
    if entitlement.get("application-identifier") not in expected_ids:
        raise ValueError("Provisioning profile does not match the app's explicit bundle ID.")
    if entitlement.get("com.apple.developer.team-identifier") != team:
        raise ValueError("Profile entitlement has a different Apple team.")
    if ("ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices")
            or entitlement.get("get-task-allow", False)
            or not entitlement.get("beta-reports-active", False)):
        raise ValueError("Use an App Store Connect distribution profile, not development, Ad Hoc, or Enterprise.")
    # Xcode matches the profile's identifier as a string, not a normalized UUID.
    # Apple currently issues lowercase identifiers; keep the signed value intact.
    profile_uuid = profile.get("UUID", "")
    if not isinstance(profile_uuid, str) or not re.fullmatch(
            r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", profile_uuid):
        raise ValueError("Provisioning profile must have a canonical UUID.")
    uuid.UUID(profile_uuid)
    certs = profile.get("DeveloperCertificates", [])
    if len(certs) != 1 or not isinstance(certs[0], bytes):
        raise ValueError("The App Store Connect profile must contain one distribution certificate.")
    return profile_uuid, hashlib.sha1(certs[0]).hexdigest().upper()


def build_number(env):
    parts = [env.get("GITHUB_RUN_NUMBER", ""), env.get("GITHUB_RUN_ATTEMPT", "")]
    if not all(part.isdigit() and int(part) > 0 for part in parts):
        raise ValueError("GitHub run number and attempt are required for a unique build number.")
    if int(parts[0]) > 9999 or int(parts[1]) > 99:
        raise ValueError("Build counter exceeds CFBundleVersion limits; update the versioning scheme.")
    return ".".join(parts)


def marketing_version(env):
    # Use GitHub's durable counter, not a version commit that triggers another run.
    # Failed/PR runs may leave gaps. Retrying a run keeps its marketing version.
    series = env.get("THIMVALE_VERSION_SERIES", "0.1")
    if not re.fullmatch(r"(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})", series):
        raise ValueError("THIMVALE_VERSION_SERIES must be a numeric major.minor pair.")
    return series + "." + build_number(env).split(".")[0]


def export_options(team, profile_uuid, certificate):
    return {
        "method": "app-store-connect", "destination": "upload",
        "teamID": team, "signingStyle": "manual", "signingCertificate": certificate,
        "provisioningProfiles": {BUNDLE_ID: profile_uuid},
        "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
        # Eligible for internal and external testing; this does NOT submit App Review.
        "testFlightInternalTestingOnly": False,
    }


def validate_app_info(info, number, version):
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleDisplayName") != "Thimvale":
        raise ValueError("The archive is not the expected Thimvale app.")
    if info.get("CFBundleVersion") != number:
        raise ValueError("The archive does not have the expected build number.")
    if info.get("CFBundleShortVersionString") != version:
        raise ValueError("The archive does not have the expected marketing version.")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        raise ValueError("The archive must include the reviewed Boolean encryption-exemption declaration.")
    if 2 in info.get("UIDeviceFamily", []) and not info.get("UIRequiresFullScreen", False):
        orientations = set(info.get("UISupportedInterfaceOrientations~ipad",
                                    info.get("UISupportedInterfaceOrientations", [])))
        required = {"UIInterfaceOrientation" + suffix for suffix in (
            "Portrait", "PortraitUpsideDown", "LandscapeLeft", "LandscapeRight")}
        if not required.issubset(orientations):
            raise ValueError("iPad multitasking requires all four interface orientations.")


def run(args, **kwargs):
    # Build tools and dependency scripts do not need secrets in their environment.
    kwargs.setdefault("env", {key: value for key, value in os.environ.items() if key not in REQUIRED})
    result = subprocess.run([str(arg) for arg in args], check=False, **kwargs)
    if result.returncode:
        # CalledProcessError would include arguments, potentially including passwords.
        raise RuntimeError(f"{args[0]} failed with exit code {result.returncode}; inspect the preceding tool output.")
    return result


def upload(env):
    preflight(env)
    if (env.get("GITHUB_ACTIONS") != "true" or env.get("RUNNER_ENVIRONMENT") != "github-hosted"
            or env.get("GITHUB_REF") != "refs/heads/main"
            or env.get("GITHUB_EVENT_NAME") not in ("push", "workflow_dispatch")):
        raise ValueError("Uploads are restricted to main on disposable GitHub-hosted runners.")
    number = build_number(env)
    version = marketing_version(env)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="thimvale-signing-", dir=env["RUNNER_TEMP"]) as temporary:
        root = Path(temporary)
        keychain = root / "signing.keychain-db"
        key_path = root / ("AuthKey_" + env["APP_STORE_CONNECT_KEY_ID"] + ".p8")
        certificate_path = root / "distribution.p12"
        profile_path = root / "distribution.mobileprovision"
        profile_plist = root / "profile.plist"
        certificate_path.write_bytes(decode_secret(env["IOS_DISTRIBUTION_P12_BASE64"], "IOS_DISTRIBUTION_P12_BASE64"))
        profile_path.write_bytes(decode_secret(env["IOS_PROVISIONING_PROFILE_BASE64"], "IOS_PROVISIONING_PROFILE_BASE64"))
        key_path.write_text(env["APP_STORE_CONNECT_PRIVATE_KEY"])
        run(["security", "cms", "-D", "-i", profile_path, "-o", profile_plist])
        with profile_plist.open("rb") as handle:
            profile_uuid, fingerprint = validate_profile(plistlib.load(handle), env["APPLE_TEAM_ID"])
        # Parsing with -noout also works with macOS's LibreSSL; never emit key text.
        run(["openssl", "pkey", "-in", key_path, "-noout"], stdout=subprocess.DEVNULL)
        # Xcode 16+ profile cache. It is disposable and restored even if signing fails.
        installed_profile = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles" / (profile_uuid + ".mobileprovision")
        previous_profile = installed_profile.read_bytes() if installed_profile.exists() else None
        original_keychains = run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout
        original_keychains = re.findall(r'"([^"]+)"', original_keychains)
        keychain_created = False
        try:
            password = secrets.token_urlsafe(32)
            run(["security", "create-keychain", "-p", password, keychain], stdout=subprocess.DEVNULL)
            keychain_created = True
            run(["security", "set-keychain-settings", "-lut", "21600", keychain], stdout=subprocess.DEVNULL)
            run(["security", "unlock-keychain", "-p", password, keychain], stdout=subprocess.DEVNULL)
            run(["security", "import", certificate_path, "-P", env["IOS_DISTRIBUTION_P12_PASSWORD"],
                 "-k", keychain, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], stdout=subprocess.DEVNULL)
            run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain], stdout=subprocess.DEVNULL)
            run(["security", "list-keychains", "-d", "user", "-s", keychain, *original_keychains])
            identities = run(["security", "find-identity", "-v", "-p", "codesigning", keychain], capture_output=True, text=True).stdout
            if fingerprint not in identities.upper():
                raise ValueError("The P12 must include the valid certificate and private key selected in the profile.")
            installed_profile.parent.mkdir(parents=True, exist_ok=True)
            installed_profile.write_bytes(profile_path.read_bytes())
            export_path = root / "ExportOptions.plist"
            with export_path.open("wb") as handle:
                plistlib.dump(export_options(env["APPLE_TEAM_ID"], profile_uuid, fingerprint), handle)
            archive_path = root / "Thimvale.xcarchive"
            print(f"Archiving Thimvale {version} ({number}) from {env.get('GITHUB_SHA', 'main')}", flush=True)
            run(["xcodebuild", "archive", "-project", "Thimvale.xcodeproj", "-scheme", "Thimvale",
                 "-configuration", "Release", "-destination", "generic/platform=iOS",
                 "-archivePath", archive_path, "-derivedDataPath", root / "DerivedData",
                 "THIMVALE_CODE_SIGN_STYLE=Manual", "THIMVALE_CODE_SIGN_IDENTITY=" + fingerprint,
                 "THIMVALE_DEVELOPMENT_TEAM=" + env["APPLE_TEAM_ID"], "THIMVALE_PROVISIONING_PROFILE=" + profile_uuid,
                 "CURRENT_PROJECT_VERSION=" + number, "MARKETING_VERSION=" + version])
            app = archive_path / "Products/Applications/Thimvale.app"
            with (app / "Info.plist").open("rb") as handle:
                info = plistlib.load(handle)
            validate_app_info(info, number, version)
            if not (app / "PrivacyInfo.xcprivacy").exists():
                raise ValueError("The archive is missing the privacy manifest.")
            run(["codesign", "--verify", "--deep", "--strict", app])
            run(["xcodebuild", "-exportArchive", "-archivePath", archive_path,
                 "-exportOptionsPlist", export_path, "-exportPath", root / "Export",
                 "-authenticationKeyPath", key_path, "-authenticationKeyID", env["APP_STORE_CONNECT_KEY_ID"],
                 "-authenticationKeyIssuerID", env["APP_STORE_CONNECT_ISSUER_ID"]])
            with open(env["GITHUB_STEP_SUMMARY"], "a") as summary:
                summary.write(f"## TestFlight upload\n\nUploaded Thimvale `{version}` (`{number}`) from `{env['GITHUB_SHA']}`. "
                              "Apple must finish processing and export-compliance checks before installation. "
                              "An internal group with automatic distribution receives eligible builds.\n")
        finally:
            if previous_profile is not None:
                installed_profile.write_bytes(previous_profile)
            else:
                installed_profile.unlink(missing_ok=True)
            subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_keychains], check=False, stdout=subprocess.DEVNULL)
            if keychain_created:
                subprocess.run(["security", "delete-keychain", str(keychain)], check=False, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["preflight"]:
            preflight(os.environ)
            print("Required release configuration is present. No credentials were printed.")
        elif sys.argv[1:] == ["upload"]:
            upload(os.environ)
        else:
            raise ValueError("Usage: python3 scripts/release.py preflight|upload")
    except (ValueError, RuntimeError, OSError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)
