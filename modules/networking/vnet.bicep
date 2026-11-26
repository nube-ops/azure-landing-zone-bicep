targetScope = 'resourceGroup'
param name string
param location string
param tags object = {}
param addressPrefixes array
param subnets array = []   // [{ name, addressPrefix }]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: addressPrefixes }
    subnets: [for s in subnets: { name: s.name, properties: { addressPrefix: s.addressPrefix } }]
  }
}
output id string = vnet.id
