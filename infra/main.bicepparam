using 'main.bicep'

param deploymentMode = readEnvironmentVariable('DR_DEPLOYMENT_MODE', 'all')
param prefix = readEnvironmentVariable('DR_PREFIX', 'drsandbox')
param primaryLocation = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param secondaryLocation = readEnvironmentVariable('DR_SECONDARY_LOCATION', 'westus2')
param linuxVmCount = int(readEnvironmentVariable('DR_LINUX_VM_COUNT', '2'))
param deployWindowsVm = bool(readEnvironmentVariable('DR_DEPLOY_WINDOWS_VM', 'true'))
param adminUsername = readEnvironmentVariable('DR_VM_ADMIN_USERNAME', 'azureuser')
param adminPassword = readEnvironmentVariable('DR_VM_ADMIN_PASSWORD', '')
param sqlAadAdminName = readEnvironmentVariable('DR_SQL_AAD_ADMIN_NAME', '')
param sqlAadAdminObjectId = readEnvironmentVariable('DR_SQL_AAD_ADMIN_OID', '')
param sqlAadAdminTenantId = readEnvironmentVariable('DR_SQL_AAD_ADMIN_TENANT', '')
param appServiceSkuName = readEnvironmentVariable('DR_APP_SERVICE_SKU', 'P0v3')
