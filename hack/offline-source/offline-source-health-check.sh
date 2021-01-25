#!/bin/bash

set -o nounset
set -e

# Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

# Source offline-source variable
WORK_HOME=$1
source ${WORK_HOME}/offline-source-variable.conf
LOG_FILE="${LOG_PATH}/health_check_file_`date +%y-%m-%d`.log"

function print_log() {
  log_type=$1
  log_message=$2
  case ${log_type} in
    info )
      echo -e "${GREEN_COL} `date +%y/%m/%d-%H:%M:%S` ${log_message} ${NORMAL_COL}" >> ${LOG_FILE}
      ;;
    warning )
      echo -e "${YELLOW_COL} `date +%y/%m/%d-%H:%M:%S` ${log_message} ${NORMAL_COL}" >> ${LOG_FILE}
      ;;
    error )
      echo -e "${RED_COL} `date +%y/%m/%d-%H:%M:%S` ${log_message} ${NORMAL_COL}" >> ${LOG_FILE}
      ;;
  esac
}

function log_clean() {
  find ${LOG_PATH} -mtime +30 -name "health_check_file_.*.log" -exec rm -rf {} \; || true
}

function restart_offline_source() {
  # Ensure image exist
  if ! ctr i ls | grep -Eqi ${CABIN_NGINX_IMAGE}; then
    CABIN_NGINX_IMAGE=`find ${PACKAGE_SOURCE_ROOT}/resources/images/save -name '*.tar.gz' -type f | xargs -I {} ctr i import {} | awk '{print $2}'`
  fi

  # Start infra-nginx
  if `ctr tasks ls | grep -Eqi ${PACKAGE_SOURCE_CONTAINERD_NAME}`; then
    ctr tasks kill --signal SIGKILL ${PACKAGE_SOURCE_CONTAINERD_NAME} >> /dev/null 2>&1 || true
    ctr tasks rm ${PACKAGE_SOURCE_CONTAINERD_NAME} >> /dev/null 2>&1 || true
  fi
  if `ctr snapshot ls | grep -Eqi ${PACKAGE_SOURCE_CONTAINERD_NAME}`; then
    ctr snapshot rm ${PACKAGE_SOURCE_CONTAINERD_NAME} >> /dev/null 2>&1 || true
  fi
  if `ctr container ls | grep -Eqi ${PACKAGE_SOURCE_CONTAINERD_NAME}`; then
    ctr container rm ${PACKAGE_SOURCE_CONTAINERD_NAME} >> /dev/null 2>&1 || true
  fi
  ctr run -d --net-host \
    --log-uri file://${PACKAGE_SOURCE_NGINX_LOG_FILE} \
    --mount type=bind,src=${COMMON_MIRROR_DIR},dst=/usr/share/nginx/html,options=rbind:r \
    ${CABIN_NGINX_IMAGE} ${PACKAGE_SOURCE_CONTAINERD_NAME}
  return 0
}

function health_check() {
  health_check=`curl -I -o /dev/null -s -w %{http_code} ${CHECK_URL}` || true
  sleep 1
  if [ $health_check == 200 ];then
    print_log info "Offline source container is health"
  else
    print_log info "Offline source container is unhealth, will start container"
    restart_offline_source
    sleep 3
    health_check
  fi
}

print_log info "Start health check"

if health_check; then
  print_log info "Health check finish !"
else
  print_log error "Health check error, Please check !"
fi

log_clean
