def GenerateConfig(context):
  
  deployment = context.env["deployment"]
  project = context.env["project"]  
  name = context.env["name"] + "-it"
  zone = context.properties["zone"]
  username = context.properties["userName"]
  password = context.properties["password"]
  sshpubkey = context.properties["sshPubKey"]
  network = "chef-network"
  statusConfigUrl = context.properties["statusConfigUrl"]
  statusVariablePath = context.properties["statusVariablePath"]
  statusUptimeDeadline = context.properties["statusUptimeDeadline"]

  resources = []
  outputs = []

  resources.append({
      'name': name,
      'type': 'compute.v1.instanceTemplate',
      'properties': {
        'properties':{
          'zone': zone,
          'machineType': "g1-small",
          'canIpForward': True,
          'disks': [{
              'deviceName': 'boot',
              'type': 'PERSISTENT',
              'boot': True,
              'autoDelete': True,
              'initializeParams': {
                  'sourceImage': 'projects/debian-cloud/global/images/family/debian-9',
                  'diskType': 'pd-standard',
                  'diskSizeGb': 10
              }
          }],
          'networkInterfaces': [{
                              'network': '$(ref.{}.selfLink)'.format(network),
                              'subnetwork': '$(ref.{}-subnet.selfLink)'.format(network),
                              'accessConfigs': [{
                                  'name': 'External NAT',
                                  'type': 'ONE_TO_ONE_NAT'
                                }]
          }],
          'serviceAccounts': [{
            'email': 'default',
            'scopes': ['https://www.googleapis.com/auth/cloud-platform']
          }],
          'tags': {'items': ["http-server", "ssh-server", "all-ports"]},
          'metadata': {
              'items': [{
                          'key': 'username',
                          'value': username
                        },
                        {
                          'key': 'status-config-url',
                          'value': statusConfigUrl
                        },
                        {
                          'key': 'status-variable-path',
                          'value': statusVariablePath
                        },
                        {
                          'key': 'status-uptime-deadline',
                          'value': statusUptimeDeadline
                        },
                        {
                          'key': 'startup-script',
                          'value': """
                                #!/bin/bash 
                                useradd -m -s /bin/bash {username}
                                echo {username}:{password} | chpasswd
                                usermod -aG sudo {username}
                                mkdir ~{username}/.ssh
                                echo {sshpubkey} > ~{username}/.ssh/authorized_keys
                                chown -R {username} ~{username}/.ssh
                                chmod -R go-rwx ~{username}/.ssh
                                echo "Done adding new user {username}"
                                {context}
                                sleep 60
                                result=$?
                                if [ $result -eq 0 ]; then
                                  curl --connect-timeout 120 --max-time 120 --retry 5 --retry-delay 0 --retry-max-time 60 -sfH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/attributes/ssh-keys" | python3 -c "import sys; [print(k) for k in [key.strip().split(':')[-1] for key in sys.stdin.readlines()]]" >> ~{username}/.ssh/authorized_keys
                                fi
                                """.format(
                                    username = username,
                                    password = password,    
                                    sshpubkey = sshpubkey,
                                    context = '\n'.join([' '*32 + i for i in context.imports["node_startup_script.sh"].split('\n')])
                                    )
                        }
              ]
            }
          }
        }
    }) 

  resources.append({
      'name': "{}-waiter".format(name),
      'type': 'runtimeconfig.v1beta1.waiter',
      'metadata': {
          'dependsOn': [name],
      },
      'properties': {
          'parent': '$(ref.{}-config.name)'.format(context.env["deployment"]),
          'waiter': "{}-waiter".format(name),
          'timeout': '{}s'.format(statusUptimeDeadline),
          'success': {
              'cardinality': {
                  'number': 5,
                  'path': '{}/success'.format(statusVariablePath),
              },
          },
          'failure': {
              'cardinality': {
                  'number': 1,
                  'path': '{}/failure'.format(statusVariablePath),
              },
          },
      },
    }) 

  outputs.append({
      'name': 'instanceTemplateSelfLink',
      'value': '$(ref.{}-it.selfLink)'.format(context.env["name"])
      })
  
  return {'resources': resources, 'outputs': outputs}
