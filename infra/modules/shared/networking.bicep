param prefix string
param primaryLocation string
param secondaryLocation string
param tags object

var primaryVnetName = '${prefix}-vnet-${primaryLocation}'
var secondaryVnetName = '${prefix}-vnet-${secondaryLocation}'

resource primaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: primaryVnetName
  location: primaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'iaas-subnet'
        properties: {
          addressPrefix: '10.20.1.0/24'
        }
      }
      {
        name: 'test-failover-subnet'
        properties: {
          addressPrefix: '10.20.2.0/24'
        }
      }
    ]
  }
}

resource secondaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: secondaryVnetName
  location: secondaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.30.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'iaas-subnet'
        properties: {
          addressPrefix: '10.30.1.0/24'
        }
      }
      {
        name: 'test-failover-subnet'
        properties: {
          addressPrefix: '10.30.2.0/24'
        }
      }
    ]
  }
}

output primaryVnetId string = primaryVnet.id
output secondaryVnetId string = secondaryVnet.id
output primaryIaasSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', primaryVnet.name, 'iaas-subnet')
output secondaryIaasSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', secondaryVnet.name, 'iaas-subnet')
output primaryTestFailoverSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', primaryVnet.name, 'test-failover-subnet')
output secondaryTestFailoverSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', secondaryVnet.name, 'test-failover-subnet')
