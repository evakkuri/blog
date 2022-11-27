// aks.bicep
// Azure Kubernetes Cluster setup

// Parameters
@description('Azure region to which to deploy resources')
@allowed([
  'westeurope'
  'northeurope'
])
param location string

@description('''
IP ranges of developers as an array of objects. Is set as the allowed IPs on AKS control API.
See template deploy.bicep for more details.
''')
param developerIpRanges array

@description('Resource ID of subnet to which cluster nodes will be deployed')
param nodeSubnetId string

// Variables
var devAksClusterName = 'clusterceptionaks'

// Managed Identities for linking 
resource aksControlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'clusterception-msi-aks-controlplane'
  location: location
}

resource aksKubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'clusterception-msi-aks-kubelet'
  location: location
}

resource managedIdentityOperatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'f1a07417-d97a-45cb-824c-7a7467783830'
}

resource aksControlPlaneIdentityManagedIdentityOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aksControlPlaneIdentity.name, managedIdentityOperatorRole.id)
  scope: aksKubeletIdentity
  properties: {
    principalId: aksControlPlaneIdentity.properties.principalId
    roleDefinitionId: managedIdentityOperatorRole.id
    principalType: 'ServicePrincipal'
  }
}

// AKS Cluster
resource devAks 'Microsoft.ContainerService/managedClusters@2022-09-02-preview' = {
  name: devAksClusterName
  dependsOn: [
    aksControlPlaneIdentityManagedIdentityOperator
  ]
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksControlPlaneIdentity.id}': {}
    }
  }
  properties: {
    identityProfile: {
      kubeletidentity: {
        clientId: aksKubeletIdentity.properties.clientId
        objectId: aksKubeletIdentity.properties.principalId
        resourceId: aksKubeletIdentity.id
      }
    }
    aadProfile: {
      adminGroupObjectIDs: [
        
      ]
      enableAzureRBAC: true
      managed: true
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
    disableLocalAccounts: true
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      dockerBridgeCidr: '172.17.0.1/16'
      dnsServiceIP: '10.2.0.10'
      serviceCidr: '10.2.0.0/24'
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
				osDiskSizeGB: 0
				mode: 'System'
        count: 2
				vmSize: 'Standard_DS2_v2'
				osType: 'Linux'
				enableNodePublicIP: false
				vnetSubnetID: nodeSubnetId
      }
    ]
    nodeResourceGroup: '${devAksClusterName}-managed-rg'
    publicNetworkAccess: 'Enabled'
    apiServerAccessProfile: {
      authorizedIPRanges: developerIpRanges
    }
    dnsPrefix: devAksClusterName
  }
}

// Outputs
output aksControlPlaneIdentity object = aksControlPlaneIdentity
output aksKubeletIdentity object = aksKubeletIdentity
