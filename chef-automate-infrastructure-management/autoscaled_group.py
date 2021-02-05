def GenerateConfig(context):
  
  zone = context.properties["zone"]
  targetSize = context.properties["targetSize"]
  instanceTemplate = context.properties["instanceTemplate"]

  resources = [{
      'name': context.env["name"] + '-igm',
      'type': 'compute.v1.instanceGroupManager',
      'properties': {
        'zone': zone,
        'targetSize': targetSize,
        'baseInstanceName': context.env["name"] + '-instance',
        'instanceTemplate': instanceTemplate
      }
  }, {
      'name': context.env["name"] + '-as',
      'type': 'compute.v1.autoscaler',
      'properties': {
        'zone': zone,
        'target': '$(ref.{}-igm.selfLink)'.format(context.env["name"]),
        'autoscalingPolicy':{
            'minNumReplicas': targetSize,
            'maxNumReplicas': targetSize,
            }
      }
  }]
  
  return {'resources': resources}
