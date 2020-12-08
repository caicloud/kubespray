#!/bin/bash
input=$1
input=${input:=install}

set -o nounset
set -e

# Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

# create directory
DEPLOY_ROOT=$(cd $(dirname "${BASH_SOURCE}")/ && pwd -P)
CONFIG_DIR=${DEPLOY_ROOT}/.config
SSH_CERT_DIR=${DEPLOY_ROOT}/ssh_cert
DEPLOY_CONTAINER_NAME="cluster-deploy-job"
REGISTRY_AUTH=`cat env.yml | grep registry_auth | awk '{print $2}' | sed 's#"##g'`

mkdir -p ${CONFIG_DIR}/registry_ca_cert

# source cargo env
if [ -f ../.install-env.sh ];then
  source ../.install-env.sh
elif [ -f ./registry_ca_cert/registry-ca.crt ]; then
  CARGO_CFG_CA_PATH="registry_ca_cert/registry-ca.crt"
  CARGO_CFG_DOMAIN=`cat env.yml | grep registry_domain | awk '{print $2}' | sed 's#"##g'`
  CARGO_CFG_IP=`cat env.yml | grep registry_ip | awk '{print $2}' | sed 's#"##g'`
  if ! `cat /etc/hosts | grep -Eqi ${CARGO_CFG_DOMAIN}`; then
    echo "${CARGO_CFG_IP} ${CARGO_CFG_DOMAIN}" >> /etc/hosts
  fi
else
  echo -e "$RED_COL Cargo env file or registry ca certificate not exist. Please check $NORMAL_COL"
  exit 1
fi

# Uniform certificate authority
if [ -f ${SSH_CERT_DIR}/id_rsa ]; then
  chmod 600 ${SSH_CERT_DIR}/id_rsa
  if [ $? -ne 0 ]; then
    echo -e "$RED_COL chmod error please check ./ssh_certs/id_ras $NORMAL_COL"
    exit 1
  fi
  chmod 644 ${SSH_CERT_DIR}/id_rsa.pub
  if [ $? -ne 0 ]; then
    echo -e "$RED_COL chmod error please check ./ssh_certs/id_ras.pub $NORMAL_COL"
    exit 1
  fi
fi

# Copy config file to config dir
cp inventory ${CONFIG_DIR}
cp env.yml ${CONFIG_DIR}
cp -r ${SSH_CERT_DIR} ${CONFIG_DIR}
cp -r ${CARGO_CFG_CA_PATH} ${CONFIG_DIR}/registry_ca_cert

function push_image() {
  ctr i tag ${IMAGE_FALL_NAME} ${CARGO_CFG_DOMAIN}/cluster-deploy/${IMAGE_NAME} || true
  if [[ ${REGISTRY_AUTH} == "" ]]; then
    ctr i push ${CARGO_CFG_DOMAIN}/cluster-deploy/${IMAGE_NAME}
  else
    ctr i push -u ${REGISTRY_AUTH} ${CARGO_CFG_DOMAIN}/cluster-deploy/${IMAGE_NAME}
  fi
}

function initializ() {
  ALL_IMAGE_FILE_LIST=`find ./resources/images/data -type f -name "*.tar.gz"`
  for IMAGE_FILE_PATH in ${ALL_IMAGE_FILE_LIST}; do
    IMAGE_FALL_NAME=`ctr i import ${IMAGE_FILE_PATH} | awk '{print $2}'`
    IMAGE_NAME=`echo ${IMAGE_FALL_NAME} | awk -F '/cluster-deploy/' '{print $NF}'`
    push_image
  done
}

# Load dependence image
function load_deploy_image() {
  IMAGE_FILE_PATH=`find ./resources/images/save -name "${DEPLOY_CONTAINER_NAME}*"`
  IMAGE_FALL_NAME=`ctr i import ${IMAGE_FILE_PATH} | grep ${DEPLOY_CONTAINER_NAME} | awk '{print $2}'`
}

function push_deploy_image() {
  IMAGE_NAME=`echo ${IMAGE_FALL_NAME} | awk -F '/cluster-deploy/' '{print $NF}'`
  push_image
}

function cluster_deploy() {
# Start vaquita
  ctr tasks kill ${DEPLOY_CONTAINER_NAME} >/dev/null 2>&1 || true
  ctr tasks rm ${DEPLOY_CONTAINER_NAME} >/dev/null 2>&1 || true
  ctr snapshots rm ${DEPLOY_CONTAINER_NAME} >/dev/null 2>&1 || true
  ctr containers rm ${DEPLOY_CONTAINER_NAME} >/dev/null 2>&1 || true
  ctr run -t --rm \
    --net-host \
    --mount type=bind,src=${CONFIG_DIR},dst=/kubespray/config,options=rbind:rw \
    ${IMAGE_FALL_NAME} \
    ${DEPLOY_CONTAINER_NAME} \
    $1
}

case $input in
  install )
    echo -e "$GREEN_COL start install compass kernel $NORMAL_COL"
    initializ
    load_deploy_image
    push_deploy_image
    COMMAND="bash run.sh install"
    cluster_deploy "${COMMAND}"
    # Copy kubeconfig
    cp ${CONFIG_DIR}/kubectl.kubeconfig ../.kubectl.kubeconfig
    ;;
  remove )
    echo -e "$GREEN_COL remove compass kernel  $NORMAL_COL"
    load_deploy_image
    COMMAND="bash run.sh remove"
    cluster_deploy "${COMMAND}"
    ;;
  add-node )
    echo -e "$GREEN_COL add compass node  $NORMAL_COL"
    NODE_NAME=$2
    load_deploy_image
    COMMAND="bash run.sh add-node ${NODE_NAME}"
    cluster_deploy "${COMMAND}"
    ;;
  remove-node )
    echo -e "$GREEN_COL remove compass node  $NORMAL_COL"
    NODE_NAME=$2
    load_deploy_image
    COMMAND="bash run.sh remove-node ${NODE_NAME}"
    cluster_deploy "${COMMAND}"
    ;;
  add-master )
    NODE_NAME=$2
    load_deploy_image
    COMMAND="bash run.sh add-master ${NODE_NAME}"
    cluster_deploy "${COMMAND}"
    ;;
  remove-master )
    NODE_NAME=$2
    load_deploy_image
    COMMAND="bash run.sh remove-master ${NODE_NAME}"
    cluster_deploy "${COMMAND}"
    ;;
  init )
    echo -e "$GREEN_COL start init package and load image $NORMAL_COL"
    initializ
    load_deploy_image
    push_deploy_image
    ;;
  debug )
    echo -e "$GREEN_COL run compass debug mode $NORMAL_COL"
    load_deploy_image
    COMMAND="bash"
    cluster_deploy "${COMMAND}"
    ;;
esac
