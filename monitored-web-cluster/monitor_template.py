"""Creates a GCE instance template for Windows"""
import json

def GenerateConfig(context):
    
    deployment = context.env["deployment"]
    project = context.env["project"]  
    name = context.env["name"]
    zone = context.properties["zone"]
    password = context.properties["userPassword"]
    username = context.properties["userName"]
    network = "chef-network"
    networkIP = context.properties["networkIP"]
    sshpubkey = context.properties['sshpubkey']
    statusConfigUrl = context.properties["statusConfigUrl"]
    statusVariablePath = context.properties["statusVariablePath"]
    statusUptimeDeadline = context.properties["statusUptimeDeadline"]

    resources = []

    resources.append({
        'name': context.env['name'],
        'type': 'compute.v1.instance',
        'properties': {
            'zone': context.properties['zone'],
            'machineType': 'https://www.googleapis.com/compute/v1/projects/{}'
                '/zones/{}/machineTypes/{}'.format(project, zone,'n1-standard-1'),
            'disks': [{
                'deviceName': 'boot',
                'type': 'PERSISTENT',
                'boot': True,
                'autoDelete': True,
                'initializeParams': {
                    'sourceImage': 'projects/debian-cloud/global/images/family/debian-9',
                    'diskType': 'https://www.googleapis.com/compute/v1'
                    '/projects/{}/zones/{}/diskTypes/pd-standard'.format(project, zone),
                    'diskSizeGb':10
                }
            }],
            'networkInterfaces': [{
                              'network': '$(ref.{}.selfLink)'.format(network),
                              'subnetwork': '$(ref.{}-subnet.selfLink)'.format(network),
                              'accessConfigs': [{
                                  'name': 'External NAT',
                                  'type': 'ONE_TO_ONE_NAT'
                               }],
                               'networkIP': networkIP
          }],
            'serviceAccounts': [{
              'email': 'default',
              'scopes': ['https://www.googleapis.com/auth/cloud-platform']
            }],
            'tags': {'items': ["ssh-server", "http-server", "chef-network-tcp-9090", "chef-network-tcp-9117", "chef-network-tcp-9093"]},
            'metadata': {
                'items': [{
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
                                result=$?
                                sleep 30
                                if [ $result -eq 0 ]; then
                                  curl --connect-timeout 10 --max-time 5 --retry 5 --retry-delay 0 --retry-max-time 60 -sfH "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/attributes/ssh-keys" | python3 -c "import sys; [print(k) for k in [key.strip().split(':')[-1] for key in sys.stdin.readlines()]]" >> ~{username}/.ssh/authorized_keys
                                fi
                                """.format(
                                    username = username,
                                    password = password,    
                                    sshpubkey = sshpubkey,
                                    context = '\n'.join([' '*32 + i for i in context.imports["monitor_startup_script.sh"].split('\n')])
                                    )
                          },
                          {
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
                          }]
            }
        }
    })
    
    resources.append({
      'name': "{}-waiter".format(context.env['name']),
      'type': 'runtimeconfig.v1beta1.waiter',
      'metadata': {
          'dependsOn': [context.env['name']],
      },
      'properties': {
          'parent': '$(ref.{}-config.name)'.format(context.env["deployment"]),
          'waiter': "{}-waiter".format(context.env['name']),
          'timeout': '{}s'.format(statusUptimeDeadline),
          'success': {
              'cardinality': {
                  'number': 1,
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

    return {'resources': resources}
