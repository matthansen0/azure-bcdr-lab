param prefix string
param primaryLocation string
param secondaryLocation string
param sqlAadAdminName string
param sqlAadAdminObjectId string
param sqlAadAdminTenantId string

@description('App Service Plan SKU name.')
param appServiceSkuName string = 'P0v3'

param tags object

resource aspPrimary 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${prefix}-asp-${primaryLocation}'
  location: primaryLocation
  tags: tags
  sku: {
    name: appServiceSkuName
  }
  properties: {
    reserved: true
  }
}

resource aspSecondary 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${prefix}-asp-${secondaryLocation}'
  location: secondaryLocation
  tags: tags
  sku: {
    name: appServiceSkuName
  }
  properties: {
    reserved: true
  }
}

resource webPrimary 'Microsoft.Web/sites@2024-04-01' = {
  name: '${prefix}-web-${primaryLocation}'
  location: primaryLocation
  tags: tags
  properties: {
    serverFarmId: aspPrimary.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      minTlsVersion: '1.2'
    }
  }
}

resource webSecondary 'Microsoft.Web/sites@2024-04-01' = {
  name: '${prefix}-web-${secondaryLocation}'
  location: secondaryLocation
  tags: tags
  properties: {
    serverFarmId: aspSecondary.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      minTlsVersion: '1.2'
    }
  }
}

resource sqlPrimary 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: '${prefix}-sql-${primaryLocation}'
  location: primaryLocation
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      login: sqlAadAdminName
      sid: sqlAadAdminObjectId
      tenantId: sqlAadAdminTenantId
      azureADOnlyAuthentication: true
      principalType: 'User'
    }
  }
}

resource sqlSecondary 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: '${prefix}-sql-${secondaryLocation}'
  location: secondaryLocation
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      login: sqlAadAdminName
      sid: sqlAadAdminObjectId
      tenantId: sqlAadAdminTenantId
      azureADOnlyAuthentication: true
      principalType: 'User'
    }
  }
}

resource sqlDbPrimary 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlPrimary
  name: '${prefix}appdb'
  location: primaryLocation
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
  }
  properties: {
    autoPauseDelay: 60
    minCapacity: 1
  }
}

resource failoverGroup 'Microsoft.Sql/servers/failoverGroups@2023-08-01-preview' = {
  parent: sqlPrimary
  name: '${prefix}-fog'
  properties: {
    partnerServers: [
      {
        id: sqlSecondary.id
      }
    ]
    databases: [
      sqlDbPrimary.id
    ]
    readWriteEndpoint: {
      failoverPolicy: 'Manual'
    }
    readOnlyEndpoint: {
      failoverPolicy: 'Disabled'
    }
  }
}

output webAppPrimaryName string = webPrimary.name
output webAppSecondaryName string = webSecondary.name
output failoverGroupName string = failoverGroup.name
