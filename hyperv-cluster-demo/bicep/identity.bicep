// =============================================================================
// identity.bicep  — Deployment Managed Identity for GitHub Actions OIDC
// Scope: Subscription (00cd4357-ed45-4efb-bee0-10c467ff994b)
//
// Creates a user-assigned managed identity with OIDC federated credentials so
// GitHub Actions can authenticate to Azure WITHOUT an app registration or
// client secret.
//
// Deploy ONCE before running any hvlab workflows:
//   az deployment sub create \
//     --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b \
//     --location eastus \
//     --template-file hyperv-cluster-demo/bicep/identity.bicep
// =============================================================================

targetScope = 'subscription'

param location string = 'eastus'

var rgName = 'rg-hvlab-mms26-eus-01'

var tags = {
  environment: 'lab'
  workload: 'hvlab-mms26'
  owner: 'kristopherjturner'
  purpose: 'GitHub Actions deployment identity — no app registration'
}

// ── Resource Group ────────────────────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: tags
}

// ── Managed Identity + Federated Credentials (resource-group scope) ──────────
module identityModule './identity-rg.bicep' = {
  name: 'hvlab-identity-rg'
  scope: rg
  params: {
    location: location
    tags: tags
  }
}

// ── Role Assignments on this subscription ────────────────────────────────────
resource roleContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'mi-hvlab-deploy-eus-01', 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: identityModule.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
    description: 'HVLab deploy MI — Contributor on deployment subscription'
  }
}

resource roleUAA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'mi-hvlab-deploy-eus-01', 'UserAccessAdministrator')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
    principalId: identityModule.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
    description: 'HVLab deploy MI — needed to assign Key Vault role to VM managed identity'
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
output identityClientId    string = identityModule.outputs.identityClientId
output identityPrincipalId string = identityModule.outputs.identityPrincipalId
output identityResourceId  string = identityModule.outputs.identityResourceId
