// main.bicep
// Main deployment template

@allowed([
  'westeurope'
  'northeurope'
])
@description('Azure region to which to deploy the resources')
param location string = 'westeurope'

@description('Array of IP address ranges, for use in resource firewalls.')
param developerIpRanges array

@description('Common tags to apply to resources.')
param commonTags object = {
  OWNER: 'Elias Vakkuri'
  PROJECT: 'ClusterceptionBlog'
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: 'clusterception-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
  tags: commonTags

  resource aksSubnet 'subnets' existing = {
    name: 'aks'
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: 'clusterceptionacr'
  location: location
  sku: {
    name: 'Basic'
  }
}

module aks 'aks.bicep' = {
  name: '${deployment().name}_aks'
  params: {
    developerIpRanges: developerIpRanges
    location: location
    nodeSubnetId: vnet::aksSubnet.id
  }
}

resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource aksKubeletAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'aks-kubelet', acrPullRoleDefinition.id)
  scope: containerRegistry
  properties: {
    principalId: aks.outputs.aksKubeletIdentity.properties.principalId
    roleDefinitionId: acrPullRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}
