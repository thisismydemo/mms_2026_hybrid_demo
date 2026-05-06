// =============================================================================
// HV-Lab Demo Host VM — Bicep Template
// Subscription: 00cd4357-ed45-4efb-bee0-10c467ff994b
// Resource Group: rg-hvlab-mms26-eus-01
//
// Naming: Azure CAF — <type>-<workload>-<instance>-<region>-<seq>
// Deploy: az deployment group create \
//           --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b \
//           --resource-group rg-hvlab-mms26-eus-01 \
//           --template-file bicep/main.bicep \
//           --parameters @bicep/parameters/tplabs.bicepparam
// =============================================================================

@description('Azure region for all resources')
param location string = 'eastus'

@description('VM size — must support nested virtualization. M32ms = 32 vCPU / 875 GB / fits MS Family quota')
@allowed([
  'Standard_M32ms'        // preferred: 32 vCPU / 875 GB RAM — fits 40 vCPU MS Family quota
  'Standard_E48ds_v5'     // fallback: 48 vCPU / 384 GB — fits 50 vCPU E-series quota
  'Standard_E104ids_v5'   // ideal if quota raised: 104 vCPU / 672 GB / isolated / local NVMe
  'Standard_E96ds_v5'     // 96 vCPU / 672 GB
  'Standard_E64ds_v5'     // 64 vCPU / 512 GB
])
param vmSize string = 'Standard_M32ms'

@description('Admin username for the host VM')
param adminUsername string = 'hvlabadmin'

@description('Admin password for the host VM — sourced from Key Vault')
@secure()
param adminPassword string

@description('Subscription containing the existing hub VNet (tplabs sub)')
param vnetSubscriptionId string = '2caa0b8a-a1d6-4f0c-8c03-861787b8315c'

@description('Resource group containing the existing hub VNet')
param vnetResourceGroup string = 'rg-azrlmgmt-dev-eus-01'

@description('Existing VNet name')
param vnetName string = 'vnet-azrl-dev-eus-01'

@description('Existing management subnet — 10.250.1.32/27, contains hvlab IPs .45/.46/.47')
param subnetName string = 'snet-azrl-dev-eus-01'

// Resource name variables (CAF)
var vmName           = 'vm-hvlab-host01-eus-01'
var nicName          = 'nic-hvlab-host01-eus-01'
var pipName          = 'pip-hvlab-host01-eus-01'
var nsgName          = 'nsg-hvlab-host01-eus-01'
var osDiskName       = 'disk-hvlab-host01-os-eus-01'
var identityName     = 'mi-hvlab-host01-eus-01'
var storageAcctName  = 'sthvlabwitness01'   // Cloud Witness — no hyphens, max 24 chars

// IP allocation (all on existing subnet 10.250.1.0/24)
var primaryIp     = '10.250.1.45'   // host VM
var wacIp         = '10.250.1.46'   // secondary → hvwac01 nested VM
var scvmmIp       = '10.250.1.47'   // secondary → hvscvmm01 nested VM

var tags = {
  environment: 'lab'
  workload: 'hvlab-mms26'
  owner: 'kristopherjturner'
  costCenter: 'tplabs-demo'
  demoEvent: 'mms-moa-2026'
  createdBy: 'bicep'
  repo: 'thisismydemo/mms_2026_hybrid_demo'
}

// =============================================================================
// Subnet resource ID — cross-subscription reference (BGP routing requirement)
// Using resourceId() directly avoids Bicep generating extensionResourceId()
// which produces the wrong resource ID for child resources across subscriptions.
// =============================================================================
var subnetResourceId = resourceId(vnetSubscriptionId, vnetResourceGroup, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)

// =============================================================================
// User-assigned Managed Identity
// Allows host VM to read Key Vault secrets during bootstrap (no stored credentials)
// =============================================================================
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// =============================================================================
// Storage Account — Azure Blob Cloud Witness for Failover Cluster
// Free, no extra VM, eliminates quorum disk as single point of failure
// =============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAcctName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// =============================================================================
// Network Security Group
// =============================================================================
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'RDP from VNet only'
        }
      }
      {
        name: 'AllowWinRM-VNet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5985-5986'
          description: 'WinRM from VNet only'
        }
      }
      {
        name: 'AllowHTTPS-VNet'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'HTTPS for WAC vmode access from VNet'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound'
        }
      }
    ]
  }
}

// =============================================================================
// Public IP — Standard SKU static (required for outbound NAT from nested VMs)
// =============================================================================
resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// =============================================================================
// Network Interface — IP forwarding enabled, 3 IP configs
//   ipconfig-primary  → 10.250.1.45 + public IP  (host VM management)
//   ipconfig-hvwac01  → 10.250.1.46               (routes to hvwac01 nested VM)
//   ipconfig-hvscvmm01→ 10.250.1.47               (routes to hvscvmm01 nested VM)
//
// IP forwarding: Azure delivers traffic for .46/.47 to the host NIC.
// Windows routing on the host forwards it to the External vSwitch → nested VM.
// =============================================================================
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    enableIPForwarding: true
    enableAcceleratedNetworking: true
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig-primary'
        properties: {
          primary: true
          privateIPAddress: primaryIp
          privateIPAllocationMethod: 'Static'
          subnet: { id: subnetResourceId }
          publicIPAddress: { id: pip.id }
        }
      }
      {
        name: 'ipconfig-hvwac01'
        properties: {
          primary: false
          privateIPAddress: wacIp
          privateIPAllocationMethod: 'Static'
          subnet: { id: subnetResourceId }
        }
      }
      {
        name: 'ipconfig-hvscvmm01'
        properties: {
          primary: false
          privateIPAddress: scvmmIp
          privateIPAllocationMethod: 'Static'
          subnet: { id: subnetResourceId }
        }
      }
    ]
  }
}

// =============================================================================
// Host VM — Standard_E96ds_v5: 96 vCPU / 672 GB RAM (nested virtualization)
// OS: Windows Server 2022 Datacenter (Gen2)
// Data disks: 4 × 1 TB Premium SSD (striped via Storage Spaces = D:\HyperVStorage)
// =============================================================================
resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: 'hvlabhost01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: false
        patchSettings: { patchMode: 'Manual' }
        timeZone: 'Central Standard Time'
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        diskSizeGB: 256
        managedDisk: { storageAccountType: 'Premium_LRS' }
        caching: 'ReadWrite'
      }
      dataDisks: [
        {
          lun: 0
          name: 'disk-hvlab-host01-data-eus-01'
          createOption: 'Empty'
          diskSizeGB: 1024
          managedDisk: { storageAccountType: 'Premium_LRS' }
          caching: 'ReadOnly'
        }
        {
          lun: 1
          name: 'disk-hvlab-host01-data-eus-02'
          createOption: 'Empty'
          diskSizeGB: 1024
          managedDisk: { storageAccountType: 'Premium_LRS' }
          caching: 'ReadOnly'
        }
        {
          lun: 2
          name: 'disk-hvlab-host01-data-eus-03'
          createOption: 'Empty'
          diskSizeGB: 1024
          managedDisk: { storageAccountType: 'Premium_LRS' }
          caching: 'ReadOnly'
        }
        {
          lun: 3
          name: 'disk-hvlab-host01-data-eus-04'
          createOption: 'Empty'
          diskSizeGB: 1024
          managedDisk: { storageAccountType: 'Premium_LRS' }
          caching: 'ReadOnly'
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
output vmResourceId       string = vm.id
output vmName             string = vm.name
output publicIpAddress    string = pip.properties.ipAddress
output privateIpAddress   string = primaryIp
output identityClientId   string = identity.properties.clientId
output identityPrincipalId string = identity.properties.principalId
output storageAccountName  string = storageAccount.name
