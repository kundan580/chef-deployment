import types

# Runtime config and software status waiter

class PropertyError(Exception):
  """An exception raised when property values are invalid."""
  pass

def _ConfigName(context):
  """Return the short config name."""
  deployment = context.properties["deployment"]
  return '{}-config'.format(deployment)


def _ConfigUrl(context):
  """Returns the full URL to the config, including hostname."""
  RTCEndpoint = "https://runtimeconfig.googleapis.com/v1beta1"
  project = context.properties["project"]
  return '{endpoint}/projects/{project}/configs/{config}'.format(
      endpoint=RTCEndpoint,
      project=project,
      config=_ConfigName(context))


def _WaiterName(context):
  """Returns the short waiter name."""
  # This name is only used for the DM manifest entry. The actual waiter name
  # within RuntimeConfig is static, as it is scoped to the config resource.
  deployment = context.properties["deployment"]
  return '{}-waiter'.format(deployment)


def _Timeout(context):
  """Returns the timeout property or a default value if unspecified."""
  timeout = context.properties["timeout"]
  timeout = timeout
  try:
    return str(int(timeout))
  except ValueError:
    raise PropertyError('Invalid timeout value: {}'.format(timeout))


def _SuccessNumber(context):
  """Returns the successNumber property or a default value if unspecified."""
  successNumber = 8
  number = successNumber
  try:
    number = int(number)
    if number < 1:
      raise PropertyError('successNumber value must be greater than 0.')
    return number
  except ValueError:
    raise PropertyError('Invalid successNumber value: {}'.format(number))


def _FailureNumber(context):
  """Returns the failureNumber property or a default value if unspecified."""
  failureNumber = 1
  number = failureNumber
  try:
    number = int(number)
    if number < 1:
      raise PropertyError('failureNumber value must be greater than 0.')
    return number
  except ValueError:
    raise PropertyError('Invalid failureNumber value: {}'.format(number))


def _WaiterDependsOn(context):
  """Returns the waiterDependsOn property or an empty list if unspecified."""
  waiterDependsOn = context.properties["waiterDependsOn"]

  return waiterDependsOn


def _RuntimeConfig(context):
  """Constructs a RuntimeConfig resource."""
  deployment = context.properties["deployment"]
  deployment_name = deployment
  return {
      'name': _ConfigName(context),
      'type': 'runtimeconfig.v1beta1.config',
      'properties': {
          'config': _ConfigName(context),
          'description': ('Holds software readiness status for {}').format(deployment_name),
      },
  }


def _Waiter(context):
  """Constructs a waiter resource."""
  statusPath = context.properties["statusPath"]
  waiter_timeout = _Timeout(context)
  return {
      'name': _WaiterName(context),
      'type': 'runtimeconfig.v1beta1.waiter',
      'metadata': {
          'dependsOn': _WaiterDependsOn(context),
      },
      'properties': {
          'parent': '$(ref.{}.name)'.format(_ConfigName(context)),
          'waiter': 'software',
          'timeout': '{}s'.format(waiter_timeout),
          'success': {
              'cardinality': {
                  'number': _SuccessNumber(context),
                  'path': '{}/success'.format(statusPath),
              },
          },
          'failure': {
              'cardinality': {
                  'number': _FailureNumber(context),
                  'path': '{}/failure'.format(statusPath),
              },
          },
      },
  }


def GenerateConfig(context):
  """Entry function to generate the DM config."""
  statusPath = context.properties["statusPath"]
  content = {
      'resources': [
          _RuntimeConfig(context),
          _Waiter(context),
      ],
      'outputs': [
          {
              'name': 'config-url',
              'value': _ConfigUrl(context)
          },
          {
              'name': 'variable-path',
              'value': statusPath
          }
      ]
  }
  return content
