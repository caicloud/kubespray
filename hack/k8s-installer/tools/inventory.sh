#!/bin/bash
# bash inventory.sh <master_ips> <node_ips> <etcd_ips>
# like this "bash tools/inventory.sh 1.1.1.1-3 1.1.1.4-8 1.1.1.1-3"
DEPLOY_ROOT=$(cd $(dirname "${BASH_SOURCE}")/ && pwd -P)
INVENTORY="${DEPLOY_ROOT/tools/}inventory"
# match and split correct IPv4 to list
match_ips() {
    local INPUT_IPS=$*
    local IPS=""
    if ! echo ${INPUT_IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' > /dev/null; then
        IPS="$(echo ${INPUT_IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | tr '\n' ' ')"
    else
        ip_prefix="$(echo ${INPUT_IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' | cut -d '.' -f1-3)"
        ip_suffix="$(echo ${INPUT_IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' | cut -d '.' -f4 | tr '-' ' ')"
        for suffix in $(seq ${ip_suffix}); do IPS="${IPS} ${ip_prefix}.${suffix}"; done
    fi
    echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | tr '\n' ' '
}

# generate inventory template
gen_inventory_template() {
    cat > ${INVENTORY} <<EOF
[all:vars]
ansible_port=22
ansible_user=root
ansible_ssh_pass=
#ansible_ssh_private_key_file=/kubespray/config/ssh_cert/id_rsa

[all]

[kube-master]

[etcd]

[kube-node]

[calico-rr]

[k8s-cluster:children]
kube-master
kube-node
calico-rr
EOF
}

# generate inventory file
gen_inventory() {
    k8s_master_ips=$(match_ips $(echo $1))
    k8s_node_ips=$(match_ips $(echo $2))
    k8s_etcd_ips=$(match_ips $(echo $3))
    gen_inventory_template

    local count=0
    for ip in ${k8s_master_ips}; do
        count=$(($count+1))
        hostname="kube-master-${count}"
        ansible_ssh_host="ansible_host=${ip}"
        sed -i "/\[all\]/a  ${hostname} ${ansible_ssh_host}" ${INVENTORY}
        sed -i "/\[kube-master\]/a ${hostname}" ${INVENTORY}
        sed -i "/\[kube-node\]/a ${hostname}" ${INVENTORY}
        if echo "${k8s_etcd_ips}" | grep "${ip}"; then sed -i "/\[etcd\]/a ${hostname}" ${INVENTORY}; fi
    done

    local count=0
    for ip in ${k8s_node_ips};do
        count=$(($count+1))
        hostname="kube-node-${count}"
        ansible_ssh_host="ansible_host=${ip}"
        sed -i "/\[all\]/a ${hostname} ${ansible_ssh_host}" ${INVENTORY}
        sed -i "/\[kube-node\]/a ${hostname}" ${INVENTORY}
    done

    if ! echo "${k8s_master_ips}" | grep "${k8s_etcd_ips}"; then
        local count=0
        for ip in $(echo ${k8s_etcd_ips}); do
            count=$(($count+1))
            hostname="kube-etcd-${count}"
            ansible_ssh_host="ansible_host=${ip}"
            sed -i "/\[all\]/a ${hostname} ${ansible_ssh_host}" ${INVENTORY}
            sed -i "/\[etcd\]/a ${hostname}" ${INVENTORY}
        done
    fi
}

MASTER_IPS=$1
NODE_IPS=$2
ETCD_IPS=$3
ETCD_IPS=${ETCD_IPS:=$1}

gen_inventory ${MASTER_IPS} ${NODE_IPS} ${ETCD_IPS}
vi ${INVENTORY}
