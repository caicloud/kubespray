#!/bin/bash
# bash inventory.sh <master_ips> <node_ips> <etcd_ips>
# like this "bash inventory.sh 1.1.1.1-3 1.1.1.4-8 1.1.1.1-3"

# match and split correct IPv4 to list
match_ips() {
    INPUT_IPS=$*
    IPS="${INPUT_IPS}"
    if ! echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' > /dev/null; then
        IPS="$(echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | tr '\n' ' ')"
    else
        ip_prefix="$(echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' | cut -d '.' -f1-3)"
        ip_suffix="$(echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}-[[:digit:]]{1,3}' | cut -d '.' -f4 | tr '-' ' ')"
        for suffix in $(seq ${ip_suffix}); do IPS="${IPS} ${ip_prefix}.${suffix}"; done
    fi
    echo ${IPS} | egrep --only-matching -E '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}' | tr '\n' ' '
}

# generate inventory template
gen_inventory_template() {
    cat > inventory <<EOF
[all:vars]
ansible_port=22
ansible_user=root
ansible_ssh_pass=
#ansible_ssh_private_key_file=/kubespray/config/ssh_cert/id_rsa

[all]

[bastion]

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
    k8s_etcd_ips=${k8s_etcd_ips:=${k8s_master_ips}}
    gen_inventory_template

    local count=0
    for ip in ${k8s_master_ips}; do
        count=$(($count+1))
        hostname="kube-master-${count}"
        ansible_ssh_host="ansible_host=${ip}"
        sed -i- "/\[all\]/a  ${hostname} ${ansible_ssh_host}" inventory
        sed -i- "/\[kube-master\]/a ${hostname}" inventory
        sed -i- "/\[kube-node\]/a ${hostname}" inventory
        if [[ "${ip}" =~ "${k8s_etcd_ips}" ]]; then sed -i- "/\[etcd\]/a ${hostname}" inventory; fi
    done

    local count=0
    for ip in ${k8s_node_ips};do
        count=$(($count+1))
        hostname="kube-node-${count}"
        ansible_ssh_host="ansible_host=${ip}"
        sed -i- "/\[all\]/a ${hostname} ${ansible_ssh_host}" inventory
        sed -i- "/\[kube-node\]/a ${hostname}" inventory
    done

    if [ "${k8s_etcd_ips}" == "${k8s_master_ips}" ]; then
        local count=0
        for ip in $(echo ${etcd_ips}); do
            count=$(($count+1))
            hostname="kube-etcd-${count}"
            ansible_ssh_host="ansible_host=${ip}"
            sed -i- "/\[all\]/a ${hostname} ${ansible_ssh_host}" inventory
            sed -i- "/\[etcd\]/a ${hostname}" inventory
        done
    fi
}

gen_inventory $1 $2 $3
vi inventory
