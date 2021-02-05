def GenerateConfig(context):
  """Creates the firewall."""
  deployment = context.env["deployment"]
  IPv4Range = "10.0.0.0/25"
  name = "chef-network"
  region = "us-central1"
  default = "default"

  resources = [{
      'name': default,
      'type': 'compute.v1.network',
      'properties': {
          'autoCreateSubnetworks': True,
          }
      },
      {
      'name': name,
      'type': 'compute.v1.network',
      'properties': {
          'autoCreateSubnetworks': False,
          }
      },
      {
      'name': name + '-subnet',
      'type': 'compute.v1.subnetwork',
      'properties':{
          'ipCidrRange': IPv4Range,
          'network': '$(ref.{}.selfLink)'.format(name),
          'region': region
          }
      },
      {
      'name': name + '-allow-http',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["http-server"],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["80"]
              }]
          }
      },
      {
      'name': name + '-all-ports',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["all-ports"],
          'allowed':[{'IPProtocol': 'all'}]
          }
      },
      {
      'name': name + '-ssh',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["ssh-server"],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["22"]
              }]
          }
      },
      {
      'name': name + '-allow-internal-ports',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': [IPv4Range],
          'targetTags': ["{}-allow-internal-ports".format(name)],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["1-65535"]
              },
              {
              'IPProtocol': 'UDP',
              'ports': ["1-65535"]
              },
              {'IPProtocol': 'ICMP'}]
          },
      'metadata':{
          'dependsOn': [name]}
      },
      {
      'name': name + '-tcp-9090',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["{}-tcp-9090".format(name)],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["9090"]
              }]
          }
      },
      {
      'name': name + '-tcp-9093',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["{}-tcp-9093".format(name)],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["9093"]
              }]
          }
      },
      {
      'name': name + '-tcp-9100',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["{}-tcp-9100".format(name)],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["9100"]
              }]
          }
      },
      {
      'name': name + '-tcp-9117',
      'type': 'compute.v1.firewall',
      'properties':{
          'network': '$(ref.{}.selfLink)'.format(name),
          'sourceRanges': ["0.0.0.0/0"],
          'targetTags': ["{}-tcp-9117".format(name)],
          'allowed':[
              {
              'IPProtocol': 'TCP',
              'ports': ["9117"]
              }]
          }
      }

  ]

  return {'resources': resources}
