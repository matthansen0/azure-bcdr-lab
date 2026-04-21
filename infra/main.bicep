targetScope = 'resourceGroup'

@description('Deployment mode: iaas, paas, or all.')
@allowed([
  'iaas'
  'paas'
  'all'
])
param deploymentMode string = 'all'

@description('Prefix used for resource naming.')
param prefix string = 'drsandbox'

@description('Primary deployment location.')
param primaryLocation string = resourceGroup().location

@description('Secondary DR location.')
param secondaryLocation string = 'westus2'

@description('Number of Linux VMs for IaaS lab.')
@minValue(1)
@maxValue(5)
param linuxVmCount int = 2

@description('Deploy a Windows VM in IaaS lab.')
param deployWindowsVm bool = true

@description('Admin username for lab VMs.')
param adminUsername string = 'azureuser'

@secure()
@description('Admin password for Windows VM.')
param adminPassword string = ''

@description('SQL admin username for PaaS SQL servers.')
param sqlAadAdminName string = ''

@description('Object ID of the Entra ID SQL admin.')
param sqlAadAdminObjectId string = ''

@description('Tenant ID for Entra ID SQL admin.')
param sqlAadAdminTenantId string = tenant().tenantId

@description('App Service Plan SKU name for PaaS lab (e.g. F1, B1, S1, P0v3).')
param appServiceSkuName string = 'P0v3'

var tags = {
  workload: 'azure-bcdr-lab'
  deploymentMode: deploymentMode
  managedBy: 'azd'
}

module sharedNetworking 'modules/shared/networking.bicep' = {
  name: 'shared-networking'
  params: {
    prefix: prefix
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    tags: tags
  }
}

module sharedVault 'modules/shared/recoveryVault.bicep' = {
  name: 'shared-recovery-vault'
  params: {
    prefix: prefix
    location: secondaryLocation
    tags: tags
  }
}

module iaasLab 'modules/iaas/vmLab.bicep' = if (deploymentMode == 'iaas' || deploymentMode == 'all') {
  name: 'iaas-vm-lab'
  params: {
    prefix: prefix
    location: primaryLocation
    linuxVmCount: linuxVmCount
    deployWindowsVm: deployWindowsVm
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: sharedNetworking.outputs.primaryIaasSubnetId
    tags: tags
  }
}

module paasLab 'modules/paas/appServiceSql.bicep' = if (deploymentMode == 'paas' || deploymentMode == 'all') {
  name: 'paas-appservice-sql'
  params: {
    prefix: prefix
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    sqlAadAdminName: sqlAadAdminName
    sqlAadAdminObjectId: sqlAadAdminObjectId
    sqlAadAdminTenantId: sqlAadAdminTenantId
    appServiceSkuName: appServiceSkuName
    tags: tags
  }
}

output deploymentMode string = deploymentMode
output vaultName string = sharedVault.outputs.vaultName
output vaultId string = sharedVault.outputs.vaultId
output vaultPrincipalId string = sharedVault.outputs.vaultPrincipalId
output logAnalyticsWorkspaceName string = sharedVault.outputs.logAnalyticsWorkspaceName
output primaryVnetId string = sharedNetworking.outputs.primaryVnetId
output secondaryVnetId string = sharedNetworking.outputs.secondaryVnetId
output primaryIaasSubnetId string = sharedNetworking.outputs.primaryIaasSubnetId
output secondaryIaasSubnetId string = sharedNetworking.outputs.secondaryIaasSubnetId
output iaasVmNames array = deploymentMode == 'iaas' || deploymentMode == 'all' ? iaasLab!.outputs.vmNames : []
output paasWebAppPrimaryName string = deploymentMode == 'paas' || deploymentMode == 'all' ? paasLab!.outputs.webAppPrimaryName : ''
output paasSqlFailoverGroupName string = deploymentMode == 'paas' || deploymentMode == 'all' ? paasLab!.outputs.failoverGroupName : ''
