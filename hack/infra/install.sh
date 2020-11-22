#!/bin/bash

set -o nounset
umask 0022

# Assumed vars:
#

### Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

INFRA_ROOT=$(cd $(dirname "${BASH_SOURCE}")/ && pwd -P)
INFRA_FILE_DIR=$INFRA_ROOT/resources/files
DIRECTORY_NAME=$(basename "${INFRA_ROOT}")
COMPASS_DEPLOY_DIR=$(cd ${INFRA_ROOT} && cd .. && pwd -P)
COMMON_ROOT=${COMPASS_DEPLOY_DIR}/common
COMMON_MIRROR_DIR=${COMMON_ROOT}/all-in-one/mirrors
INFRA_NGINX_LOG_FILE="/var/log/infra.log"
INFR_CONTAINERD_NAME="cabin-nginx"

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
if ! [[ ${DIRECTORY_NAME} =~ ${RELEASE} ]]; then
    echo -e "$RED_COL This system is ${RELEASE}.\n The installation package does not match the current system!!! $NORMAL_COL"
    exit 1
fi

# Start install infra package
echo -e "$GREEN_COL Start installing infra package... $NORMAL_COL"

# Create dependence directory
mkdir -p ${COMPASS_DEPLOY_DIR}/common/all-in-one/mirrors
mkdir -p ${COMPASS_DEPLOY_DIR}/common/containerd

# Stop firewalld
echo -e "$GREEN_COL Stop firewalld $NORMAL_COL"
systemctl stop firewalld
systemctl disable firewalld

# Disable selinux
echo -e "$GREEN_COL Disable selinux $NORMAL_COL"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config || echo -e "$YELLOW_COL Warning: Modifying /etc/selinux/config failed $NORMAL_COL"
setenforce 0 || echo "$YELLOW_COL Warning: setenforce 0 failed"

# Untar package
echo -e "$GREEN_COL Untar deploy files $NORMAL_COL"
for i in $(ls ${INFRA_FILE_DIR}/*.tar.gz);do
   tar xvf $i -C "$COMMON_MIRROR_DIR"
done

# Configure mirror
echo -e "$GREEN_COL Configure yum $NORMAL_COL"
yum clean all || true
mv /etc/yum.repos.d /etc/yum.repos.d.`date +"%Y-%m-%d-%H-%M-%S"`.bak
mkdir -p /etc/yum.repos.d
cp "${INFRA_FILE_DIR}/CentOS-8-All-In-One-local.repo" /etc/yum.repos.d/CentOS-8-All-In-One.repo
sed -i "s|__BASE__|$COMMON_MIRROR_DIR|g" /etc/yum.repos.d/CentOS-8-All-In-One.repo
yum clean all && yum makecache

# Install containerd
## This package from https://github.com/containerd/containerd/releases/tag/v1.4.1
tar xvf ${COMMON_MIRROR_DIR}/runtime/containerd/cri-containerd-cni-1.4.1-linux-amd64.tar.gz -C /
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd

## TODO：Check containerd status

# Load images
find /compass/infra-centos8.2-kubev1.19.3/resources/images/save -name '*.tar.gz' -type f | xargs -I {} ctr i import {}
CABIN_NGINX_VERSION=`ctr i ls | grep cabin-nginx | cut -d " " -f 1`

# Start cabin-nginx
if `ctr tasks ls | grep cabin-nginx`; then
  ctr tasks kill cabin-nginx >/dev/null 2>&1 || true
  ctr tasks rm cabin-nginx >/dev/null 2>&1 || true
fi
if `ctr snapshots ls | grep cabin-nginx`; then
  ctr snapshots rm cabin-nginx >/dev/null 2>&1 || true
fi
if `ctr container ls | grep cabin-nginx`; then
  ctr container rm cabin-nginx >/dev/null 2>&1 || true
fi
ctr run -t -d --net-host \
  --log-uri file://${INFRA_NGINX_LOG_FILE} \
  --mount type=bind,src=${COMMON_MIRROR_DIR},dst=/usr/share/nginx/html,options=rbind:r \
  ${CABIN_NGINX_VERSION} ${INFR_CONTAINERD_NAME}

## Check infra package installation..
while true;do
  echo -e "$GREEN_COL Check infra package installation.. $NORMAL_COL"
  health_check=`curl -I -o /dev/null -s -w %{http_code}  http://localhost:3142/centos/8/BaseOS/repodata/repomd.xml`
  sleep 1
  if [ $health_check == 200 ];then
     echo -e "$GREEN_COL ... OK, will quit. $NORMAL_COL"
     exit 0
  else
    echo -e "$GREEN_COL ... Not OK, will retry, press ctrl-C to quit. $NORMAL_COL"
  fi
done
