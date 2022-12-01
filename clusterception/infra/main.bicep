// Main deployment template

@allowed([
  'westeurope'
  'northeurope'
])
@description('Azure region to which to deploy the resources')
param location string = 'westeurope'

@description('Array of IP address ranges, for use in resource firewalls.')
param developerIpRanges array

@description('ID of user group to set as admins for AKS cluster.')
param aksAdminGroupId string

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
        name: 'aks-nodes'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'aks-defaultpool-pods'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'aks-delegation'
              properties: {
                serviceName: 'Microsoft.ContainerService/managedClusters'
              }
            }
          ]
        }
      }
    ]
  }
  tags: commonTags

  resource aksNodeSubnet 'subnets' existing = {
    name: 'aks-nodes'
  }

  resource aksDefaultNodePoolPodSubnet 'subnets' existing = {
    name: 'aks-defaultpool-pods'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'clusterception-la'
  location: location
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
    defaultPoolNodeSubnetId: vnet::aksNodeSubnet.id
    defaultPoolPodSubnetId: vnet::aksDefaultNodePoolPodSubnet.id
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
    aksAdminGroupId: aksAdminGroupId
    commonTags: commonTags
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
