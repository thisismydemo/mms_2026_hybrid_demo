// =============================================================================
// HV-Lab Demo — Bicep Parameter File (tplabs tenant)
// Target subscription: 00cd4357-ed45-4efb-bee0-10c467ff994b
// =============================================================================

using '../main.bicep'

param location = 'eastus'
param vmSize = 'Standard_M32ms'
param adminUsername = 'hvlabadmin'

param adminPassword = getSecret(
  '2caa0b8a-a1d6-4f0c-8c03-861787b8315c',
  'rg-azrlmgmt-dev-eus-01',
  'kv-tplabs-platform',
  'hvlab-host01-admin-password'
)
