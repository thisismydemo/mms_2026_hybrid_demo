// =============================================================================
// HV-Lab Demo — Bicep Parameter File (tplabs tenant)
// Target subscription: 00cd4357-ed45-4efb-bee0-10c467ff994b
//
// Deploy command:
//   az group create \
//     --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b \
//     --name rg-hvlab-mms26-eus-01 \
//     --location eastus \
//     --tags environment=lab workload=hvlab-mms26 owner=kristopherjturner
//
//   az deployment group create \
//     --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b \
//     --resource-group rg-hvlab-mms26-eus-01 \
//     --template-file hyperv-cluster-demo/bicep/main.bicep \
//     --parameters hyperv-cluster-demo/bicep/parameters/tplabs.bicepparam
//
// PREREQUISITE: Run 03-prestage-kv-secrets.ps1 BEFORE deployment.
// All secrets referenced below must exist in kv-tplabs-platform.
// =============================================================================

using '../main.bicep'

// Region — update after running 01-find-best-region.ps1
param location = 'eastus'

// VM size — update based on region quota availability
// Standard_E104ids_v5 = 104 vCPU / 672 GB / ISOLATED hardware (preferred — best for nested virt)
//   - Dedicated physical host, no noisy neighbors
//   - Local NVMe ~3.8 TB (fast VHDX I/O during demo — ephemeral, copy from data disks on demo day)
// Standard_E96ds_v5  = 96 vCPU / 672 GB (fallback if E104ids_v5 not available in region)
// Standard_E64ds_v5  = 64 vCPU / 512 GB  (last resort — reduce cluster node vCPUs to 12 each)
param vmSize = 'Standard_E104ids_v5'

param adminUsername = 'hvlabadmin'

// Admin password sourced from Key Vault — never stored in plaintext
// Pre-stage: az keyvault secret set --vault-name kv-tplabs-platform --name hvlab-host01-admin-password --value '<password>'
param adminPassword = getSecret(
  '00cd4357-ed45-4efb-bee0-10c467ff994b',
  'rg-c01-platform-eus-01',
  'kv-tplabs-platform',
  'hvlab-host01-admin-password'
)

// Existing VNet/subnet — do NOT change these unless the tplabs topology changes
// Reason: FortiGate BGP (ASN 65421) advertises 10.250.0.0/16 to on-prem.
// Placing the host VM here makes it reachable from Azure Local cluster automatically.
param vnetResourceGroup = 'rg-c01-hub-eus-01'
param vnetName          = 'vnet-lab-prodtech-eus-connectivity-hub'
param subnetName        = 'snet-lab-prodtech-eus-connectivity-mgmt'
