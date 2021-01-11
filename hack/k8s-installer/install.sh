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
TOOLS_DIR="${DEPLOY_ROOT}/tools"
IMGAE_SYNC_DIR="${DEPLOY_ROOT}/skopeo"
REGISTRY_AUTH_USERNAME=`cat env.yml | grep image_registry_username | awk '{print $2}' | sed 's#"##g'`
REGISTRY_AUTH_PASSWORD=`cat env.yml | grep image_registry_password | awk '{print $2}' | sed 's#"##g'`

mkdir -p ${CONFIG_DIR}/registry_ca_cert

# source cargo env
if [ -f ../.install-env.sh ];then
  source ../.install-env.sh
elif [ -f ./registry_ca_cert/registry-ca.crt ]; then
  CARGO_CFG_CA_PATH="registry_ca_cert/registry-ca.crt"
  CARGO_CFG_DOMAIN=`cat env.yml | grep image_registry_domain | awk '{print $2}' | sed 's#"##g'`
  CARGO_CFG_IP=`cat env.yml | grep image_registry_ip | awk '{print $2}' | sed 's#"##g'`
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
    echo -e "$RED_COL chmod error please check ./ssh_certs/id_rsa $NORMAL_COL"
    exit 1
  fi
  chmod 644 ${SSH_CERT_DIR}/id_rsa.pub
  if [ $? -ne 0 ]; then
    echo -e "$RED_COL chmod error please check ./ssh_certs/id_rsa.pub $NORMAL_COL"
    exit 1
  fi
fi

# Copy config file to config dir
cp inventory ${CONFIG_DIR}
cp env.yml ${CONFIG_DIR}
cp -r ${SSH_CERT_DIR} ${CONFIG_DIR}
cp ${CARGO_CFG_CA_PATH} ${CONFIG_DIR}/registry_ca_cert/registry-ca.crt

# syncImages sync the images to registry
function sync_images() {
  echo -e "$YELLOW_COL load images $NORMAL_COL"
  rm -rf "${IMGAE_SYNC_DIR}" || mkdir -p ${IMGAE_SYNC_DIR}
  ${TOOLS_DIR}/skopeo login ${CARGO_CFG_DOMAIN} -u "${REGISTRY_AUTH_USERNAME}" -p "${REGISTRY_AUTH_PASSWORD}"
  tar -xf images.tar.gz
  BLOB_DIR="docker/registry/v2/blobs/sha256"
  REPO_DIR="docker/registry/v2/repositories"
  for image in $(find ${REPO_DIR} -type d -name "current"); do
    name=$(echo ${image} | awk -F '/' '{print $5"/"$6":"$9}')
    link=$(cat ${image}/link | sed 's/sha256://')
    mfs="${BLOB_DIR}/${link:0:2}/${link}/data"
    mkdir -p "${IMGAE_SYNC_DIR}/${name}" && ln ${mfs} ${IMGAE_SYNC_DIR}/${name}/manifest.json
    layers=$(grep -Eo "\b[a-f0-9]{64}\b" ${mfs} | sort -n | uniq)
    for layer in ${layers}; do
      ln ${BLOB_DIR}/${layer:0:2}/${layer}/data ${IMGAE_SYNC_DIR}/${name}/${layer}
    done
  done
  for project in $(ls ${IMGAE_SYNC_DIR}); do
    ${TOOLS_DIR}/skopeo sync --insecure-policy --src-tls-verify=false --dest-tls-verify=false \
    --src dir --dest docker ${IMGAE_SYNC_DIR}/${project} ${CARGO_CFG_DOMAIN}/${project} > /dev/null
  done
  rm -rf "${IMGAE_SYNC_DIR}" docker
  cd ${DEPLOY_ROOT}
}

# Load dependence image
function load_deploy_image() {
  IMAGE_FILE_PATH=`find ./files -name "${DEPLOY_CONTAINER_NAME}*"`
  if file ${IMAGE_FILE_PATH} | grep -Eqi "gzip compressed data"; then
    gzip -d ${IMAGE_FILE_PATH}
    IMAGE_FILE_PATH=`find ./files -name "${DEPLOY_CONTAINER_NAME}*"`
  fi
  IMAGE_FALL_NAME=`ctr i import ${IMAGE_FILE_PATH} | grep ${DEPLOY_CONTAINER_NAME} | awk '{print $2}'`
}

function push_deploy_image() {
  IMAGE_NAME=`echo ${IMAGE_FALL_NAME} | awk -F '/library/' '{print $NF}'`
  ctr i tag ${IMAGE_FALL_NAME} ${CARGO_CFG_DOMAIN}/release/${IMAGE_NAME} || true
  ctr i push -u ${REGISTRY_AUTH_USERNAME}:${REGISTRY_AUTH_PASSWORD} ${CARGO_CFG_DOMAIN}/release/${IMAGE_NAME}
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
    echo -e "$GREEN_COL start deploy kubernetes cluster $NORMAL_COL"
    sync_images
    load_deploy_image
    push_deploy_image
    COMMAND="bash run.sh install"
    cluster_deploy "${COMMAND}"
    # Copy kubeconfig
    cp ${CONFIG_DIR}/kubectl.kubeconfig.local ../.kubectl.kubeconfig
    ;;
  remove )
    echo -e "$GREEN_COL remove kubernetes cluster and all platform data $NORMAL_COL"
    load_deploy_image
    COMMAND="bash run.sh remove"
    cluster_deploy "${COMMAND}"
    ;;
  add-node )
    echo -e "$GREEN_COL add kubernetes node  $NORMAL_COL"
    NODE_NAME=$2
    load_deploy_image
    COMMAND="bash run.sh add-node ${NODE_NAME}"
    cluster_deploy "${COMMAND}"
    ;;
  remove-node )
    echo -e "$GREEN_COL remove kubernetes node  $NORMAL_COL"
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
    sync_images
    load_deploy_image
    push_deploy_image
    ;;
  debug )
    echo -e "$GREEN_COL run k8s-installer debug mode $NORMAL_COL"
    load_deploy_image
    COMMAND="bash"
    cluster_deploy "${COMMAND}"
    ;;
esac
