

#!/bin/bash

set -e

DEFAULT_UPTIME_DEADLINE="300" # 5 minutes
CHEF_SHA256="6c897581b151204b5ee28a905384a12e79fbe66445922cac5645d45fc3c23cd5"
SHARE="/share"
CHEF_DIR="$SHARE/.chef"
COOKBOOKS="$SHARE/cookbooks"
CLOUD_PATH="project-edit-usr/5_5_1"
KNIFE_FILE_NAME="knife.rb"
KNIFE_FILE="$CHEF_DIR/$KNIFE_FILE_NAME"
CLOUD_KNIFE_FILE="$CLOUD_PATH/$KNIFE_FILE_NAME"
GET_CHEF_KEY_FILE_NAME="get_chef_key.sh"
GET_CHEF_KEY_FILE="$SHARE/$GET_CHEF_KEY_FILE_NAME"
CLOUD_CHEF_KEY_FILE="$CLOUD_PATH/$GET_CHEF_KEY_FILE_NAME"
PROJECT_KEY="$SHARE/project_key"
CHEF_APACHE2_DIR="$COOKBOOKS/chef_apache2"
RECIPES_DIR="$CHEF_APACHE2_DIR/recipes"
TEMPLATES_DIR="$CHEF_APACHE2_DIR/templates"
RECIPE_NAME="default.rb"
TEMPLATE_NAME="index.html.erb"
METADATA_NAME="metadata.rb"
METADATA_FILE="$CHEF_APACHE2_DIR/$METADATA_NAME"
CLOUD_METADATA="$CLOUD_PATH/$METADATA_NAME"
RECIPE_FILE="$RECIPES_DIR/$RECIPE_NAME"
TEMPLATE_FILE="$TEMPLATES_DIR/$TEMPLATE_NAME"
CLOUD_RECIPE="$CLOUD_PATH/$RECIPE_NAME"
CLOUD_TEMPLATE="$CLOUD_PATH/$TEMPLATE_NAME"
MANAGE_NODES_NAME="manage_nodes.sh"
MANAGE_NODES_FILE="$SHARE/$MANAGE_NODES_NAME"
CLOUD_MANAGE_NODES_FILE="$CLOUD_PATH/$MANAGE_NODES_NAME"

function metadata_value() {
  curl --retry 5 -sfH "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/$1"
}

function access_token() {
  metadata_value "instance/service-accounts/default/token" \
    | python -c "import sys, json; print json.load(sys.stdin)['access_token']"
}

function retrieve_script() {
  curl --retry 5 -sf \
    "http://storage.googleapis.com/${1}" \
    -o "${2}"
}

function uptime_seconds() {
  seconds="$(cat /proc/uptime | cut -d' ' -f1)"
  echo "${seconds%%.*}" # delete floating point.
}

function user_name() {
  metadata_value "instance/attributes/username"
}

function user_password() {
  metadata_value "instance/attributes/password"
}


function config_url() {
  metadata_value "instance/attributes/status-config-url"
}

function instance_id() {
  metadata_value "instance/id"
}

function variable_path() {
  metadata_value "instance/attributes/status-variable-path"
}

function server_name() {
  metadata_value "instance/attributes/server-name"
}

function ssh_pub_key() {
  metadata_value "instance/attributes/ssh-pub-key"
}

function project_name() {
  metadata_value "project/project-id"
}

function create_new_ssh_key() {
  ssh-keygen -t rsa -f $PROJECT_KEY -N '' -C "${1}"
}

function get_new_ssh_key() {
  echo "$(cat /share/project_key.pub)"
}

function fingerprint() {
  curl --retry 5 -sfH "Authorization: Bearer $(access_token)" \
    "https://www.googleapis.com/compute/v1/projects/$(project_name)" \
    | python -c "import sys, json; print json.load(sys.stdin)['commonInstanceMetadata']['fingerprint']"
}

function get_key_json() {
  _USER="${1}"
  printf '{"fingerprint":"%s", "items": [{"key":"ssh-keys", "value":"%s:%s\\n%s:%s %s"}]}' "$(fingerprint)" "${_USER}" "$(get_new_ssh_key)" "${_USER}" "$(ssh_pub_key)" "${_USER}"
}

function add_ssh_key() {
  curl --retry 5 -sfH "Authorization: Bearer $(access_token)" \
    -H "Content-Type: application/json" \
    -X POST -d "$(get_key_json "${1}")" \
    "https://www.googleapis.com/compute/v1/projects/$(project_name)/setCommonInstanceMetadata"
}

function uptime_deadline() {
  metadata_value "instance/attributes/status-uptime-deadline" \
    || echo $DEFAULT_UPTIME_DEADLINE
}

function config_name() {
  _prefix="https://runtimeconfig.googleapis.com/v1beta1/"
  _config_url=$(config_url)
  _config_name="${_config_url#$_prefix}"
  echo "${_config_name}"
}

function variable_body() {
  encoded_value=$(echo "$2" | base64)
  printf '{"name":"%s", "value":"%s"}\n' "${1}" "$encoded_value"
}

function post_result() {
  var_subpath=$1
  var_value=$2
  var_path="$(config_name)/variables/$var_subpath/$(instance_id)"

  curl --retry 5 -sH "Authorization: Bearer $(access_token)" \
    -H "Content-Type: application:json" \
    -X POST -d "$(variable_body "$var_path" "$var_value")" \
    "$(config_url)/variables"
}

function post_success() {
  if [[ ! -z "$2" ]]; then
    post_result "$2/success" "${1:-Success}"
  else
    post_result "$(variable_path)/success" "${1:-Success}"
  fi
}

function post_failure() {
  if [[ ! -z "$2" ]]; then
    post_result "$2/failure" "${1:-Failure}"
  else
    post_result "$(variable_path)/failure" "${1:-Failure}"
  fi
}

function check_success() {
  # custom success checks go here
  dpkg -l chefdk && \
  [[ -f $KNIFE_FILE ]] && \
  [[ -f $GET_CHEF_KEY_FILE ]] && \
  [[ -f $MANAGE_NODES_FILE ]] && \
  [[ -f $RECIPE_FILE ]] && \
  [[ -f $TEMPLATE_FILE ]] && \
  [[ -f $METADATA_FILE ]] && \
  [[ $(chef --version | grep 'Chef Development Kit Version:' | awk '{print $5}') == '3.1.0' ]]
}

function install_chef() {
  CHEF_DEB="/tmp/chef-install.deb" && \
  wget -O $CHEF_DEB https://packages.chef.io/files/stable/chefdk/3.1.0/debian/9/chefdk_3.1.0-1_amd64.deb && \
  CHEF_SHA256_DOWNLOAD=$(sha256sum $CHEF_DEB | awk '{print $1}') && \
  [[ $CHEF_SHA256_DOWNLOAD == "$CHEF_SHA256" ]] && \
  dpkg -i $CHEF_DEB
}

function custom_init() {
  # custom init commands go here
  _USER_NAME=$(user_name) && \
  _USER_PASSWORD=$(user_password) && \
  CORRECTED_USER_NAME=$(echo "$_USER_NAME" | sed -e 's/-/_/g') && \
  GET_ZONE=$(metadata_value "instance/zone" | python3 -c "import sys; print(sys.stdin.readlines()[0].split('/')[-1])") && \
  CHEF_SERVER_FQDN="$(server_name).$GET_ZONE.c.$(project_name).internal" && \
  apt-get update && apt-get install -y git && install_chef && \
  mkdir $SHARE $CHEF_DIR $COOKBOOKS $CHEF_APACHE2_DIR $RECIPES_DIR $TEMPLATES_DIR && \
  retrieve_script $CLOUD_KNIFE_FILE $KNIFE_FILE && \
  retrieve_script $CLOUD_CHEF_KEY_FILE $GET_CHEF_KEY_FILE && \
  sed -i '11a\GET_ZONE=$(metadata_value "instance/zone" | python3 -c "import sys; print(sys.stdin.readlines()[0].split('\'/\'')[-1])")\n' $GET_CHEF_KEY_FILE && \
  sed -i "s/\.c\./\.\$GET_ZONE\.c\./g" $GET_CHEF_KEY_FILE && \
  retrieve_script $CLOUD_MANAGE_NODES_FILE $MANAGE_NODES_FILE && \
  retrieve_script $CLOUD_RECIPE $RECIPE_FILE && \
  retrieve_script $CLOUD_TEMPLATE $TEMPLATE_FILE && \
  retrieve_script $CLOUD_METADATA $METADATA_FILE && \
  sed -i "s/CHEF_SERVER/$CHEF_SERVER_FQDN/g" $KNIFE_FILE && \
  sed -i "s/--identity-file/-P $_USER_PASSWORD --ssh-identity-file/g" $MANAGE_NODES_FILE && \
  create_new_ssh_key "$CORRECTED_USER_NAME" && \
  add_ssh_key "$CORRECTED_USER_NAME" && \
  chgrp -R google-sudoers $SHARE && \
  chmod -R 775 $SHARE && \
  chmod -R 777 $CHEF_DIR && \
  chmod 777 $TEMPLATE_FILE
}

function check_success_with_retries() {
  deadline="$(uptime_deadline)"
  while [[ "$(uptime_seconds)" -lt "$deadline" ]]; do
    message=$(check_success)
    case $? in
      0)
        # Success
        return 0
        ;;
      1)
        # Not ready; continue loop
        ;;
      *)
        # Failure
        echo "$message"
        return 1
        ;;
    esac

    sleep 5
  done

  # The check was not successful within the required deadline.
  echo "status check timeout"
  return 1
}

function do_init() {
  # Run the init script first. If no init script was specified, this is a no-op
  echo "software-status: initializing..."

  set +e
  message="$(custom_init)"
  result=$?
  set -e

  if [[ $result -ne 0 ]]; then
    echo "software-status: init failure"
    post_failure "$message"
    post_failure "$message" "status"
    return 1
  fi
}

function do_check() {
  # Poll for success.
  echo "software-status: waiting for software to become ready..."
  set +e
  message="$(check_success_with_retries)"
  result=$?
  set -e

  if [[ $result -eq 0 ]]; then
    echo "software-status: success"
    post_success
    post_success "Success" "status"
  else
    echo "software-status: failed with message: $message"
    post_failure "$message"
    post_failure "$message" "status"
  fi
}

# Run the initialization script synchronously.
do_init || exit $?

# Run checks and drop them into the background as to not block the shell
do_check & disown
