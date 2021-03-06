#!/bin/bash

set -e

DEFAULT_UPTIME_DEADLINE="300" # 5 minutes
CHEF_SERVER_CORE="chef-server-core"
CHEF_SHA256="4ab1655336588e0b7b67bc779bff648273d53fddb393831fcdc7d359339460af"

function metadata_value() {
  curl --retry 5 -sfH "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/$1"
}

function access_token() {
  metadata_value "instance/service-accounts/default/token" \
    | python -c "import sys, json; print json.load(sys.stdin)['access_token']"
}

function uptime_seconds() {
  seconds="$(cat /proc/uptime | cut -d' ' -f1)"
  echo "${seconds%%.*}" # delete floating point.
}

function user_name() {
  metadata_value "instance/attributes/username"
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

function project_name() {
  metadata_value "project/project-id"
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
  printf '{"name":"%s", "value":"%s"}\n' "$1" "$encoded_value"
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
  dpkg -l $CHEF_SERVER_CORE
}

function install_chef_server() {
  CHEF_DEB="/tmp/$CHEF_SERVER_CORE-install.deb" && \
  wget -O $CHEF_DEB https://packages.chef.io/files/stable/chef-server/12.16.14/ubuntu/16.04/chef-server-core_12.16.14-1_amd64.deb && \
  CHEF_SHA256_DOWNLOAD=$(sha256sum $CHEF_DEB | awk '{print $1}') && \
  [[ $CHEF_SHA256_DOWNLOAD == "$CHEF_SHA256" ]] && \
  dpkg -i $CHEF_DEB && chef-server-ctl reconfigure

  until (curl -D - http://localhost:8000/_status) | grep "200 OK"; do sleep 5s; done
  while (curl http://localhost:8000/_status) | grep "fail"; do sleep 5s; done

  chef-server-ctl user-create chefadmin Chef Admin admin@example.io insecurepassword --filename /share/chefadmin.pem && \
  chef-server-ctl org-create chefexample "Chef Example, Inc." --association_user chefadmin --filename /share/chef-admin-validator.pem
}

function custom_init() {
  # custom init commands go here
  mkdir /share && install_chef_server
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
