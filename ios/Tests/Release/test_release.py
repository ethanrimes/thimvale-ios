import base64
import datetime as dt
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[2] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def app_info(self):
        return {"CFBundleIdentifier": release.BUNDLE_ID, "CFBundleDisplayName": "Thimvale",
                "CFBundleVersion": "12.1", "CFBundleShortVersionString": "0.1.12", "UIDeviceFamily": [1, 2],
                "ITSAppUsesNonExemptEncryption": False,
                "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientation" + suffix for suffix in (
                    "Portrait", "PortraitUpsideDown", "LandscapeLeft", "LandscapeRight")]}

    def test_valid_archive_metadata(self):
        release.validate_app_info(self.app_info(), "12.1", "0.1.12")

    def test_archive_identity_and_build_number_must_match(self):
        for key in ("CFBundleIdentifier", "CFBundleDisplayName", "CFBundleVersion", "CFBundleShortVersionString"):
            info = self.app_info()
            info[key] = "wrong"
            with self.assertRaises(ValueError):
                release.validate_app_info(info, "12.1", "0.1.12")

    def test_ipad_archive_requires_all_orientations(self):
        info = self.app_info()
        info["UISupportedInterfaceOrientations~ipad"].remove("UIInterfaceOrientationPortraitUpsideDown")
        with self.assertRaisesRegex(ValueError, "all four"):
            release.validate_app_info(info, "12.1", "0.1.12")

    def test_archive_requires_explicit_boolean_encryption_declaration(self):
        for value in (None, True, "NO", "false", 0):
            info = self.app_info()
            if value is None:
                del info["ITSAppUsesNonExemptEncryption"]
            else:
                info["ITSAppUsesNonExemptEncryption"] = value
            with self.assertRaisesRegex(ValueError, "Boolean encryption-exemption"):
                release.validate_app_info(info, "12.1", "0.1.12")

    def profile(self):
        return {
            "UUID": "6DF6BA6A-146B-42C1-986B-6122B09464F7", "TeamIdentifier": ["ABCDE12345"],
            "ApplicationIdentifierPrefix": ["OLDPREFIX1"],
            "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30),
            "DeveloperCertificates": [b"fixture-certificate-not-a-real-key"],
            "Entitlements": {"application-identifier": "OLDPREFIX1." + release.BUNDLE_ID,
                             "com.apple.developer.team-identifier": "ABCDE12345", "beta-reports-active": True},
        }

    def test_valid_profile_allows_legacy_app_identifier_prefix(self):
        profile_uuid, certificate = release.validate_profile(self.profile(), "ABCDE12345")
        self.assertEqual(profile_uuid, self.profile()["UUID"])
        self.assertEqual(len(certificate), 40)

    def test_wrong_app_and_team_rejected(self):
        profile = self.profile()
        profile["Entitlements"]["application-identifier"] = "OLDPREFIX1.com.other.app"
        with self.assertRaisesRegex(ValueError, "bundle ID"):
            release.validate_profile(profile, "ABCDE12345")
        with self.assertRaisesRegex(ValueError, "different Apple team"):
            release.validate_profile(self.profile(), "OTHER12345")

    def test_profile_uuid_preserves_apple_casing_through_export(self):
        for identifier in (self.profile()["UUID"], self.profile()["UUID"].lower()):
            with self.subTest(identifier=identifier):
                profile = self.profile()
                profile["UUID"] = identifier
                selected, certificate = release.validate_profile(profile, "ABCDE12345")
                self.assertEqual(selected, identifier)
                self.assertEqual(release.export_options("ABCDE12345", selected, certificate)[
                    "provisioningProfiles"][release.BUNDLE_ID], identifier)

    def test_noncanonical_profile_uuid_rejected(self):
        for value in (None, "", "../profile", self.profile()["UUID"].replace("-", "")):
            profile = self.profile()
            profile["UUID"] = value
            with self.assertRaisesRegex(ValueError, "canonical UUID"):
                release.validate_profile(profile, "ABCDE12345")

    def test_development_adhoc_and_enterprise_rejected(self):
        for key, value in (("ProvisionedDevices", ["device"]), ("ProvisionsAllDevices", True)):
            profile = self.profile(); profile[key] = value
            with self.assertRaisesRegex(ValueError, "distribution profile"):
                release.validate_profile(profile, "ABCDE12345")
        for key, value in (("get-task-allow", True), ("beta-reports-active", False)):
            profile = self.profile(); profile["Entitlements"][key] = value
            with self.assertRaises(ValueError):
                release.validate_profile(profile, "ABCDE12345")

    def test_expired_profile_rejected(self):
        profile = self.profile()
        profile["ExpirationDate"] = dt.datetime(2020, 1, 1)
        with self.assertRaisesRegex(ValueError, "expired"):
            release.validate_profile(profile, "ABCDE12345")

    def test_build_numbers_include_retry_and_reject_injection(self):
        self.assertEqual(release.build_number({"GITHUB_RUN_NUMBER": "24", "GITHUB_RUN_ATTEMPT": "2"}), "24.2")
        for value in ("", "0", "1; command", "10000"):
            with self.assertRaises(ValueError):
                release.build_number({"GITHUB_RUN_NUMBER": value, "GITHUB_RUN_ATTEMPT": "1"})

    def test_patch_increments_for_each_new_run(self):
        first = {"GITHUB_RUN_NUMBER": "14", "GITHUB_RUN_ATTEMPT": "1"}
        self.assertEqual(release.marketing_version(first), "0.1.14")
        self.assertEqual(release.marketing_version(dict(first, GITHUB_RUN_NUMBER="15")), "0.1.15")

    def test_retry_keeps_patch_but_increments_build(self):
        retry = {"GITHUB_RUN_NUMBER": "14", "GITHUB_RUN_ATTEMPT": "2"}
        self.assertEqual(release.marketing_version(retry), "0.1.14")
        self.assertEqual(release.build_number(retry), "14.2")

    def test_major_minor_series_is_configurable_and_validated(self):
        env = {"GITHUB_RUN_NUMBER": "14", "GITHUB_RUN_ATTEMPT": "1", "THIMVALE_VERSION_SERIES": "1.2"}
        self.assertEqual(release.marketing_version(env), "1.2.14")
        for series in ("", "1", "1.2.3", "1.02", "-1.2", "1.2; command", "10000.0"):
            with self.assertRaisesRegex(ValueError, "major.minor"):
                release.marketing_version(dict(env, THIMVALE_VERSION_SERIES=series))

    def test_export_uploads_without_submitting_for_review(self):
        options = release.export_options("ABCDE12345", "profile", "certificate")
        self.assertEqual(options["destination"], "upload")
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["provisioningProfiles"], {release.BUNDLE_ID: "profile"})
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertFalse(options["testFlightInternalTestingOnly"])

    def test_base64_validation(self):
        self.assertEqual(release.decode_secret(base64.b64encode(b"fixture").decode() + "\n", "TEST"), b"fixture")
        with self.assertRaisesRegex(ValueError, "TEST"):
            release.decode_secret("not base64!!!", "TEST")

    def test_missing_secrets_report_names_not_values(self):
        with self.assertRaisesRegex(ValueError, "Missing GitHub configuration: APPLE_TEAM_ID"):
            release.preflight({})

    def test_secret_formats_and_non_hosted_upload_rejected(self):
        env = {key: "fixture" for key in release.REQUIRED}
        with self.assertRaisesRegex(ValueError, "10-character"):
            release.preflight(env)
        env.update(APPLE_TEAM_ID="ABCDE12345", APP_STORE_CONNECT_KEY_ID="KEYID12345",
                   APP_STORE_CONNECT_ISSUER_ID="6DF6BA6A-146B-42C1-986B-6122B09464F7",
                   APP_STORE_CONNECT_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----")
        for key in ("IOS_DISTRIBUTION_P12_BASE64", "IOS_PROVISIONING_PROFILE_BASE64"):
            env[key] = base64.b64encode(b"fixture").decode()
        release.preflight(env)
        with self.assertRaisesRegex(ValueError, "disposable GitHub-hosted"):
            release.upload(env)


if __name__ == "__main__":
    unittest.main()
