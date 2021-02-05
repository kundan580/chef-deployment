#!/bin/bash

set -e

DEFAULT_UPTIME_DEADLINE="300" # 5 minutes
SHARE="/share"
PRO_SHA256="4779d5cf08c50ed368a57b102ab3895e5e830d6b355ca4bfecf718a034a164e0"
PROMETHEUS_VERSION="prometheus-1.7.1.linux-amd64"
PRO_TAR="/tmp/${PROMETHEUS_VERSION}.tar.gz"
PRO_URL="https://github.com/prometheus/prometheus/releases/download/v1.7.1/${PROMETHEUS_VERSION}.tar.gz"
PRO_DIR="${SHARE}/${PROMETHEUS_VERSION}"
ALERT_VERSION="alertmanager-0.9.1.linux-amd64"
ALERT_SHA256="407e0311689207b385fb1252f36d3c3119ae9a315e3eba205aaa69d576434ed7"
ALERT_DIR="${SHARE}/${ALERT_VERSION}"
ALERT_TAR="/tmp/${ALERT_VERSION}.tar.gz"
ALERT_URL="https://github.com/prometheus/alertmanager/releases/download/v0.9.1/${ALERT_VERSION}.tar.gz"
CLOUD_PATH="project-edit-usr/5_7_1"
PRO_YML_NAME="prometheus.yml"
CLOUD_PRO_YML="${CLOUD_PATH}/${PRO_YML_NAME}"
PRO_YML="${SHARE}/${PRO_YML_NAME}"
ALERT_YML_NAME="alertmanager.yml"
CLOUD_ALERT_YML="${CLOUD_PATH}/${ALERT_YML_NAME}"
ALERT_YML="${SHARE}/${ALERT_YML_NAME}"
RULES_CONF_NAME="rules.conf"
CLOUD_RULES_CONF="${CLOUD_PATH}/${RULES_CONF_NAME}"
RULES_CONF="${SHARE}/${RULES_CONF_NAME}"

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

function check_prometheus() {
  # check the successful exection and teardown of prometheus
  prometheus &
  if [[ $? -eq 0 ]]; then
    kill "$(ps aux | grep 'prometheus' | grep -v grep | awk '{print $2}')"
  fi
}

function check_alertmanager() {
  # check the successful exection and teardown of alertmanager
  alertmanager &
  if [[ $? -eq 0 ]]; then
    kill "$(ps aux | grep 'alertmanager' | grep -v grep | awk '{print $2}')"
  fi
}

function check_success() {
  # custom success checks go here
  [[ -f $PRO_YML ]] && \
  [[ -f $ALERT_YML ]] && \
  [[ -f $RULES_CONF ]] && \
  check_prometheus && \
  check_alertmanager
}

function install_prometheus() {
  # Install Prometheus to /share
  wget -O $PRO_TAR $PRO_URL && \
  PRO_DOWN_SHA256=$(sha256sum $PRO_TAR | awk '{print $1}') && \
  [[ $PRO_SHA256 == "$PRO_DOWN_SHA256" ]] && \
  tar xvfz $PRO_TAR -C $SHARE && \
  retrieve_script $CLOUD_PRO_YML $PRO_YML && \
  retrieve_script $CLOUD_RULES_CONF $RULES_CONF && \
  ln -s $PRO_DIR/prometheus /usr/bin
}

function install_alertmanager() {
  # Install Alertmanager to /share
  wget -O $ALERT_TAR $ALERT_URL && \
  ALERT_DOWN_SHA256=$(sha256sum $ALERT_TAR | awk '{print $1}') && \
  [[ $ALERT_SHA256 == "$ALERT_DOWN_SHA256" ]] && \
  tar xvfz $ALERT_TAR -C $SHARE && \
  retrieve_script $CLOUD_ALERT_YML $ALERT_YML && \
  ln -s $ALERT_DIR/alertmanager /usr/bin
}

function custom_init() {
  # custom init commands go here
  mkdir $SHARE && \
  install_prometheus && \
  install_alertmanager && \
  chgrp -R google-sudoers $SHARE && \
  chmod -R 777 $SHARE && \
  chmod -R 777 $PRO_YML
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
