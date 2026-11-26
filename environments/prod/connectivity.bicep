targetScope = 'subscription'

import { resourceName } from '../../modules/naming.bicep'
import { resolveTags } from '../../modules/resource-groups/tags.bicep'

param location string = deployment().location
param environment string
param regionCode string
param hubAddressPrefix string = '10.0.0.0/22'

// Workload key: must match its entry in workloads.json and its management group suffix.
var workload = 'connectivity'
var tags = resolveTags(loadJsonContent('workloads.json').workloads, workload, environment)

module connectivityRg '../../modules/resource-groups/resourceGroup.bicep' = {
  name: 'deploy-${workload}-rg'
  params: {
    resourceGroupName: resourceName('rg', 'net', 'hub', environment, regionCode, 1)
    location: location
    tags: tags
  }
}

module hubVnet '../../modules/networking/vnet.bicep' = {
  name: 'deploy-${workload}-hub-vnet'
  scope: resourceGroup(resourceName('rg', 'net', 'hub', environment, regionCode, 1))
  dependsOn: [connectivityRg]
  params: {
    name: resourceName('vnet', 'net', 'hub', environment, regionCode, 1)
    location: location
    tags: tags
    addressPrefixes: [hubAddressPrefix]
  }
}

output connectivityResourceGroupName string = connectivityRg.outputs.name
