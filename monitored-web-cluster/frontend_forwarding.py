def GenerateConfig(context):
  
  deployment = context.env["deployment"]
  project = context.env["project"]
  frontend = context.properties["frontend"]
  port = context.properties["port"]

  resources = [{
      'name': '{}-urlmap'.format(deployment),
      'type': 'compute.v1.urlMap',
      'properties': {
      		'defaultService': '$(ref.{}-bes.selfLink)'.format(frontend),
      		'hostRules': [{'hosts': ['*'],
      					   'pathMatcher': 'pathmap'}],
      		'pathMatchers': [{'name': 'pathmap',
      		                  'defaultService': '$(ref.{}-bes.selfLink)'.format(frontend)}]
        }
    },
    {
      'name': '{}-targetproxy'.format(deployment),
      'type': 'compute.v1.targetHttpProxy',
      'properties': {
      		'urlMap': '$(ref.{}-urlmap.selfLink)'.format(deployment)
        }
    },
    {
      'name': '{}-forwarding'.format(deployment),
      'type': 'compute.v1.globalForwardingRule',
      'properties': {
      		'IPProtocol': 'TCP',
      		'portRange': port,
      		'target': '$(ref.{}-targetproxy.selfLink)'.format(deployment)
        }
    }
    ]
  
  return {'resources': resources}
