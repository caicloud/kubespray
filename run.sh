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

if ! [[ -d ${CONFIG_PATH} ]]; then
  echo -e "\033[1;31m Config path not exist, Please check \033[0m"
  exit 1
fi

# Copy from config path
rm -f ${INVENTORY_PATH}/env.yml ${INVENTORY_PATH}/inventory
cp -f ${CONFIG_PATH}/env.yml ${INVENTORY_PATH}/env.yml
cp -f ${CONFIG_PATH}/inventory ${INVENTORY_PATH}/inventory

case $input in
  install-gpu )
# TODO: add gpu device install
    exit 0
    ;;
  install )
# TODO: add install layer
    echo -e "\033[32m       ############ Start install cluster ################       \033[0m"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      cluster.yml
    ;;
  remove )
    echo -e "\033[32m       ############ Start remove cluster #################       \033[0m"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      -e reset_confirmation=yes --skip-tags='mounts' \
      reset.yml
    ;;
  add-node )
    NODE_NAME=$2
    echo -e "\033[32m       ############ Start add work node ##################       \033[0m"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      --limit=${NODE_NAME} \
      scale.yml
    ;;
  remove-node )
    NODE_NAME=$2
    reset_nodes=false
    echo -e "\033[32m       ############ Start remove work node ###############       \033[0m"
    # about 3mins
    if [[ -n $3 ]] && [[ x$3 = "xnot-reset" ]]; then
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node=${NODE_NAME} -e delete_nodes_confirmation=yes -e reset_nodes=false \
        remove-node.yml
    else
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node=${NODE_NAME} -e delete_nodes_confirmation=yes
        remove-node.yml
    fi
    ;;
  add-master )
    echo -e "\033[32m       ############ Start add master node ################       \033[0m"
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
      cluster.yml
    # restart every node nginx service
    ansible -i ${INVENTORY_PATH}/inventory kube-node -m shell -a "crictl stop `crictl ps | grep nginx-proxy | awk '{print $1}'`"
    ;;
  remove-master )
    NODE_NAME=$2
    echo -e "\033[32m       ############ Start remove master node #############       \033[0m"
    if [[ -n $3 ]] && [[ x$3 = "xnot-reset" ]]; then
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node=${NODE_NAME} -e delete_nodes_confirmation=yes -e reset_nodes=false \
        remove-node.yml
    else
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node=${NODE_NAME} -e delete_nodes_confirmation=yes \
        remove-node.yml
    fi
    ;;
  add-etcd )
    echo -e "\033[32m       ############ Start add etcd node ##################       \033[0m"
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
    echo -e "\033[32m       ############ Start remove etcd node ###############       \033[0m"
    # remove etcd node
    if [[ -n $3 ]] && [[ x$3 = "xnot-reset" ]]; then
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node="${NODE_NAME}" -e delete_nodes_confirmation=yes -e reset_nodes=false \
        remove-node.yml
    else 
      ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" \
        -e node=\"${NODE_NAME}\" -e delete_nodes_confirmation=yes \
        remove-node.yml
    fi

    # modify etcd node message
    sed -i "${NODE_NAME}/d" ${INVENTORY_PATH}/inventory

    # update etcd config in cluster
    ansible-playbook -i ${INVENTORY_PATH}/inventory -e "@${INVENTORY_PATH}/env.yml" cluster.yml
    ;;
esac
