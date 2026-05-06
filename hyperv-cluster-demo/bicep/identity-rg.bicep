// identity-rg.bicep — Resource-group-scoped module called from identity.bicep
// Deploys the managed identity and its OIDC federated credentials.

targetScope = 'resourceGroup'

param location string
param tags object

var identityName = 'mi-hvlab-deploy-eus-01'

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource federatedCredMain 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-actions-hvlab-main'
  properties: {
    issuer:    'https://token.actions.githubusercontent.com'
    subject:   'repo:thisismydemo/mms_2026_hybrid_demo:ref:refs/heads/main'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource federatedCredDispatch 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: deployIdentity
  name: 'github-actions-hvlab-dispatch'
  dependsOn: [federatedCredMain]
  properties: {
    issuer:    'https://token.actions.githubusercontent.com'
    subject:   'repo:thisismydemo/mms_2026_hybrid_demo:environment:hvlab'
    audiences: ['api://AzureADTokenExchange']
  }
}

output identityClientId    string = deployIdentity.properties.clientId
output identityPrincipalId string = deployIdentity.properties.principalId
output identityResourceId  string = deployIdentity.id
