targetScope = 'subscription'

import { rgName } from '../../modules/resource-groups/naming.bicep'
import { resolveTags } from '../../modules/resource-groups/tags.bicep'

param location string = deployment().location
param orgName string
param environment string
param regionCode string

// Workload key: must match its entry in workloads.json and its management group suffix.
var workload = 'connectivity'
var tags = resolveTags(loadJsonContent('workloads.json').workloads, workload, environment)

module connectivityRg '../../modules/resource-groups/resourceGroup.bicep' = {
  name: 'deploy-${workload}-rg'
  params: {
    resourceGroupName: rgName('net', 'hub', environment, regionCode, 1)
    location: location
    tags: tags
  }
}

output connectivityResourceGroupName string = connectivityRg.outputs.name
