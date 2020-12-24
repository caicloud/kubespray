#!/bin/bash
input=$1
input=${input:=install}

set -o nounset
set -o errexit

### Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

## Set variable
DEPLOY_HOME=/kubespray
INVENTORY_PATH=${DEPLOY_HOME}/inventory/deploy-cluster
CONFIG_PATH=${DEPLOY_HOME}/config
SSH_CERT_PATH=${CONFIG_PATH}/ssh_cert
CONTAINER_MOUNT_PATH=${DEPLOY_HOME}/container_config

if [[ -f ${CONTAINER_MOUNT_PATH}/env.yml ]] && [[ -f ${CONTAINER_MOUNT_PATH}/inventory ]]; then
  mkdir -p ${CONFIG_PATH}
  cp -f ${CONTAINER_MOUNT_PATH}/env.yml ${CONFIG_PATH}/env.yml
  cp -f ${CONTAINER_MOUNT_PATH}/inventory ${CONFIG_PATH}/inventory
fi

if ! [[ -d ${CONFIG_PATH} ]]; then
  echo -e "${RED_COL} Config path not exist, Please check ${NORMAL_COL}"
  exit 1
fi

# Gen ssh certs and copy to every host
function ssh_certs() {
  # Ensure certs not exist
  if [[ -f ${SSH_CERT_PATH}/id_rsa ]]; then
    ansible-playbook -i ${CONFIG_PATH}/inventory --skip-tags='gen-cert' -e "rsa_cert_path=${SSH_CERT_PATH}" host-key.yml
  else
    SSH_CERT_PATH="/kubespray/config/ssh_certs"
    mkdir -p ${SSH_CERT_PATH}
    rm -rf ${SSH_CERT_PATH}/* || true
    ansible-playbook -i ${CONFIG_PATH}/inventory -e "rsa_cert_path=${SSH_CERT_PATH}" host-key.yml
  fi
  cp -f ${CONFIG_PATH}/inventory ${INVENTORY_PATH}/inventory
  sed -i "s#ansible_ssh_pass=[^ ]*#ansible_ssh_private_key_file=${SSH_CERT_PATH}/id_rsa#g" ${INVENTORY_PATH}/inventory
}

# Copy from config path
rm -f ${INVENTORY_PATH}/env.yml ${INVENTORY_PATH}/inventory
cp -f ${CONFIG_PATH}/env.yml ${INVENTORY_PATH}/env.yml

if cat ${CONFIG_PATH}/inventory | grep -v "^#" | grep -Eqi "ansible_ssh_pass=" ; then
  ssh_certs
elif cat ${CONFIG_PATH}/inventory | grep -v "^#" | grep -Eqi "ansible_ssh_private_key_file=" ; then
  cp -f ${CONFIG_PATH}/inventory ${INVENTORY_PATH}/inventory
else
  echo -e "${RED_COL} Can't find the host auth config, Please check inventory file. ${NORMAL_COL}"
  exit 1
fi

case $input in
  init-machine )
# TODO: add gpu device install
    exit 0
    ;;
  install )
# TODO: add install layer
    echo -e "${GREEN_COL}       ############ Start install cluster ################       ${NORMAL_COL}"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      cluster.yml
    ;;
  remove )
    echo -e "${GREEN_COL}       ############ Start remove cluster #################       ${NORMAL_COL}"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      -e reset_confirmation=yes --skip-tags='mounts' \
      reset.yml
    ;;
  add-node )
    NODE_NAME=$2
    echo -e "${GREEN_COL}       ############ Start add work node ##################       ${NORMAL_COL}"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      --limit=${NODE_NAME} \
      scale.yml
    ;;
  remove-node )
    NODE_NAME=$2
    reset_nodes=false
    echo -e "${GREEN_COL}       ############ Start remove work node ###############       ${NORMAL_COL}"
    # about 3mins
    EXTERNEL_CONFIG=""
    [[ $# == "3" ]] && [[ x$3 == "xnot-reset" ]] && EXTERNEL_CONFIG="-e reset_nodes=false" || true
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      -e node=${NODE_NAME} -e delete_nodes_confirmation=yes ${EXTERNEL_CONFIG} \
      remove-node.yml
    ;;
  add-master )
    echo -e "${GREEN_COL}       ############ Start add master node ################       ${NORMAL_COL}"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      cluster.yml
    # restart every node nginx service
    ansible -i ${INVENTORY_PATH}/inventory kube-node -m shell -a "crictl stop `crictl ps | grep nginx-proxy | awk '{print $1}'`"
    ;;
  remove-master )
    NODE_NAME=$2
    echo -e "${GREEN_COL}       ############ Start remove master node #############       ${NORMAL_COL}"
    EXTERNEL_CONFIG=""
    [[ $# == "3" ]] && [[ x$3 == "xnot-reset" ]] && EXTERNEL_CONFIG="-e reset_nodes=false" || true
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      -e node=${NODE_NAME} -e delete_nodes_confirmation=yes ${EXTERNEL_CONFIG} \
      remove-node.yml
    ;;
  add-etcd )
    echo -e "${GREEN_COL}       ############ Start add etcd node ##################       ${NORMAL_COL}"
    # add etcd node
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      --limit=etcd,kube-master -e ignore_assert_errors=yes -e etcd_retries=20 \
      cluster.yml

    # update etcd config in cluster
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      --limit=etcd,kube-master -e ignore_assert_errors=yes -e etcd_retries=20 \
      upgrade-cluster.yml
    ;;
  remove-etcd )
    NODE_NAME=$2
    echo -e "${GREEN_COL}       ############ Start remove etcd node ###############       ${NORMAL_COL}"
    # remove etcd node
    EXTERNEL_CONFIG=""
    [[ $# == "3" ]] && [[ x$3 == "xnot-reset" ]] && EXTERNEL_CONFIG="-e reset_nodes=false" || true
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      -e node="${NODE_NAME}" -e delete_nodes_confirmation=yes ${EXTERNEL_CONFIG} \
      remove-node.yml

    # modify etcd node message
    sed -i "${NODE_NAME}/d" ${INVENTORY_PATH}/inventory

    # update etcd config in cluster
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" cluster.yml
    ;;
esac
