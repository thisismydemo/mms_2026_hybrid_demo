// =============================================================================
// identity.bicep  — Deployment Managed Identity for GitHub Actions OIDC
// Scope: Subscription (00cd4357-ed45-4efb-bee0-10c467ff994b)
//
// Creates a user-assigned managed identity with a federated credential so
// GitHub Actions can authenticate to Azure WITHOUT an app registration or
// client secret. The managed identity IS the identity — no service principal.
//
// Deploy ONCE before running any hvlab workflows:
//   az deployment sub create \
//     --subscription 00cd4357-ed45-4efb-bee0-10c467ff994b \
//     --location eastus \
//     --template-file hyperv-cluster-demo/bicep/identity.bicep
// =============================================================================

targetScope = 'subscription'

param location string = 'eastus'

var identityName = 'mi-hvlab-deploy-eus-01'
var rgName       = 'rg-hvlab-mms26-eus-01'

var tags = {
  environment: 'lab'
  workload: 'hvlab-mms26'
  owner: 'kristopherjturner'
  purpose: 'GitHub Actions deployment identity — no app registration'
}

// ── Resource Group (pre-created here so identity lands somewhere) ────────────
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: tags
}

// ── User-Assigned Managed Identity ──────────────────────────────────────────
resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
  scope: rg
}

// ── Federated Credential for GitHub Actions OIDC ────────────────────────────
// No client secret ever. GitHub sends a short-lived OIDC token;
// Azure exchanges it for an access token bound to THIS managed identity.
resource federatedCred 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-actions-hvlab-main'
  properties: {
    issuer:   'https://token.actions.githubusercontent.com'
    subject:  'repo:thisismydemo/mms_2026_hybrid_demo:ref:refs/heads/main'
    audiences: ['api://AzureADTokenExchange']
  }
}

// Allow workflow_dispatch from any branch ref (for manual triggers)
resource federatedCredDispatch 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-actions-hvlab-dispatch'
  properties: {
    issuer:   'https://token.actions.githubusercontent.com'
    subject:  'repo:thisismydemo/mms_2026_hybrid_demo:environment:hvlab'
    audiences: ['api://AzureADTokenExchange']
  }
}

// ── Role Assignments on this subscription ───────────────────────────────────
// Contributor: create/manage all lab resources
resource roleContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, deployIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'HVLab deploy MI — Contributor on deployment subscription'
  }
}

// User Access Administrator: needed for workflow 01 to assign KV role to the VM's MI
resource roleUAA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, deployIdentity.id, 'UserAccessAdministrator')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
    principalId: deployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'HVLab deploy MI — needed to assign Key Vault role to VM managed identity'
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output identityClientId    string = deployIdentity.properties.clientId
output identityPrincipalId string = deployIdentity.properties.principalId
output identityResourceId  string = deployIdentity.id
