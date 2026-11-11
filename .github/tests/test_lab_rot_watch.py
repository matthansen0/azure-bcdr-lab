import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import lab_rot_watch


class PreviewApiTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.infra = Path(self.temp_dir.name)

    def write_bicep(self, name, content):
        (self.infra / name).write_text(content, encoding="utf-8")

    def test_old_stable_apis_and_required_diagnostics_preview_are_not_findings(self):
        self.write_bicep(
            "resources.bicep",
            """
resource vault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {}
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {}
// resource ignored 'Microsoft.Sql/servers@2023-08-01-preview' = {}
""",
        )
        self.assertEqual(lab_rot_watch.preview_findings(self.infra), [])

    def test_other_preview_apis_are_identified_by_resource_and_deduplicated(self):
        self.write_bicep(
            "one.bicep",
            """
resource server 'Microsoft.Sql/servers@2023-08-01-preview' = {}
resource other 'Microsoft.Other/settings@2021-05-01-preview' = {}
""",
        )
        self.write_bicep(
            "two.bicep",
            "resource second 'Microsoft.Sql/servers@2023-08-01-preview' = {}\n",
        )
        self.assertEqual(
            lab_rot_watch.preview_findings(self.infra),
            [
                "Preview apiVersion in use: Microsoft.Other/settings@2021-05-01-preview "
                "(review if a stable API version is available).",
                "Preview apiVersion in use: Microsoft.Sql/servers@2023-08-01-preview "
                "(review if a stable API version is available).",
            ],
        )

    def test_other_diagnostic_preview_versions_are_not_exempt(self):
        self.write_bicep(
            "diag.bicep",
            "resource diag 'Microsoft.Insights/diagnosticSettings@2020-01-01-preview' = {}\n",
        )
        self.assertEqual(len(lab_rot_watch.preview_findings(self.infra)), 1)

    def test_commented_declarations_are_ignored_without_discarding_strings(self):
        self.write_bicep(
            "comments.bicep",
            """
var note = 'literal /* not a comment */'
/*
resource ignored 'Microsoft.Sql/servers@2023-08-01-preview' = {}
*/
resource actual 'Microsoft.Sql/servers@2024-05-01-preview' = {}
""",
        )
        findings = lab_rot_watch.preview_findings(self.infra)
        self.assertEqual(len(findings), 1)
        self.assertIn("Microsoft.Sql/servers@2024-05-01-preview", findings[0])

    def test_multiline_strings_do_not_create_preview_findings(self):
        for prefix, content in (
            ("", "literal text"),
            ("$", "${'value'}"),
            ("$$", "$${'value'}"),
        ):
            with self.subTest(prefix=prefix):
                self.write_bicep(
                    "multiline.bicep",
                    f"var example = {prefix}'''\n"
                    "resource ignored 'Microsoft.Sql/servers@2023-08-01-preview' = {}\n"
                    f"{content}\n"
                    "'''\n"
                    "resource stable 'Microsoft.Sql/servers@2023-08-01' = {}\n",
                )
                self.assertEqual(lab_rot_watch.preview_findings(self.infra), [])

    def test_preview_declarations_around_multiline_strings_are_preserved(self):
        self.write_bicep(
            "mixed.bicep",
            """
resource first 'Microsoft.Sql/servers@2024-05-01-preview' = {}
var note = 'can\\'t start a /* comment */'
var example = '''
/* This is string content, not a Bicep comment.
resource ignored 'Microsoft.Compute/virtualMachines@2020-01-01-preview' = {}
'''
/*
''' A delimiter in a comment must not start a string.
*/
resource second 'Microsoft.Other/settings@2021-05-01-preview' = {}
var anotherExample = $'''
resource ignoredAgain 'Microsoft.Network/virtualNetworks@2020-01-01-preview' = {}
${'value // still string content'}
'''
""",
        )
        self.assertEqual(
            lab_rot_watch.preview_findings(self.infra),
            [
                "Preview apiVersion in use: Microsoft.Other/settings@2021-05-01-preview "
                "(review if a stable API version is available).",
                "Preview apiVersion in use: Microsoft.Sql/servers@2024-05-01-preview "
                "(review if a stable API version is available).",
            ],
        )

    def test_missing_infrastructure_directory_fails(self):
        with self.assertRaises(FileNotFoundError):
            lab_rot_watch.preview_findings(self.infra / "missing")

    def test_empty_infrastructure_directory_fails(self):
        with self.assertRaises(FileNotFoundError):
            lab_rot_watch.preview_findings(self.infra)


class FingerprintTests(unittest.TestCase):
    def test_legacy_age_and_finding_order_do_not_change_fingerprint(self):
        first = [
            "- [ ] Potentially stale apiVersion: 2023-04-01 (~1200 days old).",
            "- [ ] Broken local markdown link target: README.md:missing.md",
        ]
        second = [
            first[1],
            "- [ ] Potentially stale apiVersion: 2023-04-01 (~1207 days old).",
        ]
        self.assertEqual(lab_rot_watch.fingerprint(first), lab_rot_watch.fingerprint(second))

    def test_a_real_finding_change_changes_fingerprint(self):
        first = ["- [ ] Preview apiVersion in use: Microsoft.Sql/servers@2023-08-01-preview"]
        second = ["- [ ] Preview apiVersion in use: Microsoft.Sql/servers@2024-05-01-preview"]
        self.assertNotEqual(lab_rot_watch.fingerprint(first), lab_rot_watch.fingerprint(second))


if __name__ == "__main__":
    unittest.main()
