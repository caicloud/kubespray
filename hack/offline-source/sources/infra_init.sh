#!/bin/bash
## FileName: infra_init.sh

set -o nounset
umask 0022

### Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

# get download_ip
if [[ ! $1 ]]; then
    echo "$GREEN_COL bash infra_init.sh \$download_ip $NORMAL_COL"
    exit 1
else
    DOWNLOAD_IP=$1
    DOWNLOAD_URL=http://${DOWNLOAD_IP}:3142
    DOWNLOAD_PATH=${DOWNLOAD_URL}/sources
fi

SYSTEM_VERSION_ID=$(cat /etc/os-release | grep "VERSION_ID" | awk -F '=' '{print $2}' | sed 's/"//g')
CENTOS_MIRROR_FILE_NAME="CentOS-${SYSTEM_VERSION_ID}-All-In-One.repo"
CONTAINERD_VERSION="1.4.3"

echo -e "$GREEN_COL Check system version $NORMAL_COL"
# get system version
if [ `uname -i` == 'x86_64' ]; then
    if cat /etc/os-release | grep "^NAME=" | grep -Eqi "centos|red hat|redhat"; then
        RELEASE="centos"
    else
        echo -e "$RED_COL Please check system! $NORMAL_COL"
        exit 3
    fi
else
    echo -e "$RED_COL The CPU architecture is not x86 $NORMAL_COL"
fi
if [[ ${RELEASE} == '' ]]; then
    echo -e "$RED_COL Can not get system message, please check $NORMAL_COL"
    exit 1
fi

# Stop firewalld
echo -e "$GREEN_COL Stop firewalld $NORMAL_COL"
systemctl stop firewalld
systemctl disable firewalld

# Disable selinux
echo -e "$GREEN_COL Disable selinux $NORMAL_COL"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config || echo -e "$YELLOW_COL Warning: Modifying /etc/selinux/config failed $NORMAL_COL"
setenforce 0 || echo "$YELLOW_COL Warning: setenforce 0 failed"

# check containerd install or uninstall
systemctl status containerd.service >> /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    RUNNING_CONTAINERD_VERSION=`containerd --version | cut -d " " -f 3`
    if [ ${RUNNING_CONTAINERD_VERSION} != v${CONTAINERD_VERSION} ]; then
        echo -e "$GREEN_COL install docker version is ${RUNNING_CONTAINERD_VERSION} $NORMAL_COL"
        exit 0
    else
        echo -e "$GREEN_COL docker already installed ! $NORMAL_COL"
        exit 0
    fi
fi

# Configure mirror
echo -e "$GREEN_COL Configure yum $NORMAL_COL"
yum clean all || true
mv /etc/yum.repos.d /etc/yum.repos.d.`date +"%Y-%m-%d-%H-%M-%S"`.bak
mkdir -p /etc/yum.repos.d
curl ${DOWNLOAD_PATH}/${CENTOS_MIRROR_FILE_NAME} -o /etc/yum.repos.d/${CENTOS_MIRROR_FILE_NAME} || \
wget ${DOWNLOAD_PATH}/${CENTOS_MIRROR_FILE_NAME} -O /etc/yum.repos.d/${CENTOS_MIRROR_FILE_NAME}
if [[ $? -ne 0 ]]; then
    echo -e "$RED_COL download yum repo config error, Please check download_ip !! $NORMAL_COL"
    exit 2
fi
sed -i "s#__download_url__#${DOWNLOAD_URL}#g" /etc/yum.repos.d/${CENTOS_MIRROR_FILE_NAME}
yum clean all && yum makecache

# Install containerd
echo -e "$GREEN_COL Start install containerd $NORMAL_COL"
yum install -y containerd.io-${CONTAINERD_VERSION}

# Start containerd
echo -e "$GREEN_COL Starting containerd $NORMAL_COL"
systemctl restart containerd
systemctl enable containerd
