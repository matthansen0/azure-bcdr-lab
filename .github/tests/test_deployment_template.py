import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def nested_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nested_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from nested_objects(child)


class DeploymentTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        template = json.loads((ROOT / "infra" / "main.json").read_text(encoding="utf-8"))
        cls.objects = list(nested_objects(template))

    def resources(self, resource_type):
        return [obj for obj in self.objects if obj.get("type") == resource_type]

    def test_both_web_apps_use_supported_dotnet_runtime(self):
        sites = self.resources("Microsoft.Web/sites")
        self.assertEqual(len(sites), 2)
        for site in sites:
            self.assertEqual(site["properties"]["siteConfig"]["linuxFxVersion"], "DOTNETCORE|10.0")
            self.assertTrue(site["properties"]["httpsOnly"])

    def test_both_sql_servers_preserve_entra_only_authentication(self):
        servers = self.resources("Microsoft.Sql/servers")
        self.assertEqual(len(servers), 2)
        for server in servers:
            self.assertEqual(server["apiVersion"], "2023-08-01")
            self.assertTrue(server["properties"]["administrators"]["azureADOnlyAuthentication"])
            self.assertEqual(server["properties"]["administrators"]["administratorType"], "ActiveDirectory")
            self.assertNotIn("administratorLoginPassword", server["properties"])

    def test_sql_database_and_failover_group_use_stable_api(self):
        databases = self.resources("Microsoft.Sql/servers/databases")
        groups = self.resources("Microsoft.Sql/servers/failoverGroups")
        self.assertEqual(len(databases), 1)
        self.assertEqual(len(groups), 1)
        self.assertEqual(databases[0]["apiVersion"], "2023-08-01")
        self.assertEqual(databases[0]["properties"]["autoPauseDelay"], 60)
        self.assertEqual(databases[0]["properties"]["minCapacity"], 1)
        self.assertEqual(groups[0]["apiVersion"], "2023-08-01")
        self.assertEqual(groups[0]["properties"]["readWriteEndpoint"]["failoverPolicy"], "Manual")
        self.assertEqual(groups[0]["properties"]["readOnlyEndpoint"]["failoverPolicy"], "Disabled")

    def test_shared_vault_monitoring_matches_bicep_source(self):
        vaults = self.resources("Microsoft.RecoveryServices/vaults")
        diagnostics = self.resources("Microsoft.Insights/diagnosticSettings")
        self.assertEqual(len(vaults), 1)
        self.assertEqual(len(diagnostics), 1)
        self.assertEqual(vaults[0]["identity"]["type"], "SystemAssigned")
        self.assertNotIn("monitoringSettings", vaults[0]["properties"])
        self.assertEqual(
            diagnostics[0]["properties"]["logs"],
            [{"categoryGroup": "allLogs", "enabled": True}],
        )
        self.assertEqual(
            diagnostics[0]["properties"]["metrics"],
            [{"category": "AllMetrics", "enabled": True}],
        )


if __name__ == "__main__":
    unittest.main()
