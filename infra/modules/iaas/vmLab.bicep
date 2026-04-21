param prefix string
param location string
param subnetId string
param linuxVmCount int
param deployWindowsVm bool
param adminUsername string
@secure()
param adminPassword string
param tags object

var nicBase = '${prefix}-nic'
var vmBase = '${prefix}-vm'

resource pipLinux 'Microsoft.Network/publicIPAddresses@2024-05-01' = [for i in range(0, linuxVmCount): {
  name: '${prefix}-pip-linux-${i + 1}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}]

resource nicLinux 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, linuxVmCount): {
  name: '${nicBase}-linux-${i + 1}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pipLinux[i].id
          }
        }
      }
    ]
  }
}]

resource vmLinux 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, linuxVmCount): {
  name: '${vmBase}-linux-${i + 1}'
  location: location
  tags: union(tags, {
    drRole: 'source'
    drSequence: '${i + 1}'
  })
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: '${prefix}linux${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicLinux[i].id
        }
      ]
    }
  }
}]

resource windowsPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployWindowsVm) {
  name: '${prefix}-pip-win-1'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource windowsNic 'Microsoft.Network/networkInterfaces@2024-05-01' = if (deployWindowsVm) {
  name: '${nicBase}-win-1'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: windowsPip.id
          }
        }
      }
    ]
  }
}

resource vmWindows 'Microsoft.Compute/virtualMachines@2024-07-01' = if (deployWindowsVm) {
  name: '${vmBase}-win-1'
  location: location
  tags: union(tags, {
    drRole: 'source'
    drSequence: 'windows-1'
  })
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    osProfile: {
      computerName: '${prefix}win1'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: windowsNic.id
        }
      ]
    }
  }
}

var linuxVmNames = [for i in range(0, linuxVmCount): vmLinux[i].name]
output vmNames array = deployWindowsVm ? concat(linuxVmNames, [vmWindows.name]) : linuxVmNames
