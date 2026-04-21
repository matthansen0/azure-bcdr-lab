param prefix string
param location string
param tags object

// --- Log Analytics workspace for vault diagnostics ---
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource vault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: '${prefix}-rsv'
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteState: 'AlwaysON'
        softDeleteRetentionPeriodInDays: 14
      }
    }
  }
}

// --- Diagnostic settings: all ASR log categories to Log Analytics ---
resource vaultDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}-rsv-diag'
  scope: vault
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

output vaultName string = vault.name
output vaultId string = vault.id
output vaultPrincipalId string = vault.identity.principalId
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
