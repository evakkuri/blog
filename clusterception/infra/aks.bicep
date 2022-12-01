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

@description('Resource ID of subnet to which default node pool nodes will be deployed')
param defaultPoolNodeSubnetId string

@description('Resource ID of subnet to which default node pool pods will be deployed')
param defaultPoolPodSubnetId string

@description('Common tags to apply to resources')
param commonTags object

@description('Resource ID of Log Analytics Workspace for container logs')
param logAnalyticsWorkspaceId string

@description('ID of user group to set as admins for AKS cluster.')
param aksAdminGroupId string

// Variables
var devAksClusterName = 'clusterceptionaks'

// Managed Identities for linking Container Registry
resource aksControlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'clusterception-msi-aks-controlplane'
  location: location
  tags: commonTags
}

resource aksKubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'clusterception-msi-aks-kubelet'
  location: location
  tags: commonTags
}

// Control Plane identity needs the Managed Identity Operator role in order to be able to set the kubelet identity
// to the cluster
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
  tags: commonTags
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
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    }
    identityProfile: {
      kubeletidentity: {
        clientId: aksKubeletIdentity.properties.clientId
        objectId: aksKubeletIdentity.properties.principalId
        resourceId: aksKubeletIdentity.id
      }
    }
    aadProfile: {
      adminGroupObjectIDs: [
        aksAdminGroupId
      ]
      enableAzureRBAC: true
      managed: true
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
    disableLocalAccounts: false
    networkProfile: {
      networkPlugin: 'azure'
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
				vnetSubnetID: defaultPoolNodeSubnetId
        podSubnetID: defaultPoolPodSubnetId
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
