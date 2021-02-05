def GenerateConfig(context):
  
  name = context.env["name"]
  zone = context.properties["zone"]
  port = context.properties["port"]
  service = context.properties["service"]
  targetSize = 5
  userName = context.properties["userName"]
  password = context.properties["userPassword"]
  sshpubkey = context.properties["sshPubKey"]
  statusConfigUrl = context.properties["statusConfigUrl"]
  statusVariablePath = context.properties["statusVariablePath"]
  statusUptimeDeadline = context.properties["statusUptimeDeadline"]

  resources = [{
      'name': name,
      'type': 'node_instance_template.py',
      'properties': {
        'zone': zone,
        'userName': userName,
        'password': password,
        'sshPubKey': sshpubkey,
        'statusConfigUrl': statusConfigUrl,
        'statusVariablePath': statusVariablePath,
        'statusUptimeDeadline': statusUptimeDeadline,
      }
  }, {
      'name': name + "-pri",
      'type': 'autoscaled_group.py',
      'properties': {
        'zone': zone,
        'port': port,
        'service': service,
        'baseInstanceName': name + "-instance",
        'instanceTemplate': '$(ref.{}-it.selfLink)'.format(name),
        'targetSize': targetSize
      }
  }, {
      'name': name + "-hc",
      'type': 'compute.v1.httpHealthCheck',
      'properties': {
      	'port': port,
      }
  }, {
      'name': name + "-bes",
      'type': 'compute.v1.backendService',
      'properties': {
      	'port': port,
        'portName': service,
        'backends':[{
            'name': name + '-primary',
            'group': '$(ref.{}-pri-igm.instanceGroup)'.format(name),
            }],
        'healthChecks': ['$(ref.{}-hc.selfLink)'.format(name)]
      }
  }]
  
  return {'resources': resources}
