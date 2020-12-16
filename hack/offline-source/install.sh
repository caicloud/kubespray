#!/bin/bash

set -o nounset
set -e

# Set system umask. 
# If the operating system is security hardened and the umask value is modified, the permissions of the decompressed files will be wrong.
umask 0022

### Color setting
RED_COL="\\033[1;31m"           # red color
GREEN_COL="\\033[32;1m"         # green color
BLUE_COL="\\033[34;1m"          # blue color
YELLOW_COL="\\033[33;1m"        # yellow color
NORMAL_COL="\\033[0;39m"

PACKAGE_SOURCE_ROOT=$(cd $(dirname "${BASH_SOURCE}")/ && pwd -P)
PACKAGE_SOURCE_FILE_DIR=$PACKAGE_SOURCE_ROOT/resources/files
DIRECTORY_NAME=$(basename "${PACKAGE_SOURCE_ROOT}")
PRODUCT_DEPLOY_DIR=$(cd ${PACKAGE_SOURCE_ROOT} && cd .. && pwd -P)
COMMON_ROOT=${PRODUCT_DEPLOY_DIR}/common
COMMON_MIRROR_DIR=${COMMON_ROOT}/all-in-one/mirrors
PACKAGE_SOURCE_NGINX_LOG_FILE="/var/log/offline-source.log"
PACKAGE_SOURCE_CONTAINERD_NAME="offline-source-nginx"
CONTAINERD_VERSION="1.4.3"
SYSTEM_VERSION_ID=$(cat /etc/os-release | grep "VERSION_ID" | awk -F '=' '{print $2}' | sed 's/"//g')
CENTOS_MIRROR_FILE_NAME="CentOS-${SYSTEM_VERSION_ID}-All-In-One-local.repo"

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

# Start install offline source
echo -e "$GREEN_COL Start installing offline source ... $NORMAL_COL"

# Create dependence directory
mkdir -p ${PRODUCT_DEPLOY_DIR}/common/all-in-one/mirrors
mkdir -p ${PRODUCT_DEPLOY_DIR}/common/containerd

# Stop firewalld
echo -e "$GREEN_COL \tStop firewalld $NORMAL_COL"
systemctl stop firewalld
systemctl disable firewalld

# Disable selinux
echo -e "$GREEN_COL \tDisable selinux $NORMAL_COL"
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config || echo -e "$YELLOW_COL Warning: Modifying /etc/selinux/config failed $NORMAL_COL"
setenforce 0 || echo "$YELLOW_COL Warning: setenforce 0 failed"

# Untar package
echo -e "${GREEN_COL} \tUntar deploy files ${NORMAL_COL}"
for i in $(ls ${PACKAGE_SOURCE_FILE_DIR}/*.tar.gz);do
  package_name=`echo ${i} | awk -F '/' '{print $NF}'`
  echo -en "${GREEN_COL} \t\tuntar ${package_name} ... ${NORMAL_COL}"
  tar xvf $i -C "$COMMON_MIRROR_DIR" >> /dev/null 2>&1
  echo -e "${YELLOW_COL} done ${NORMAL_COL}"
done

# Configure mirror
echo -e "$GREEN_COL \tConfigure mirror $NORMAL_COL"
yum clean all >> /dev/null 2>&1 || true
mv /etc/yum.repos.d /etc/yum.repos.d.`date +"%Y-%m-%d-%H-%M-%S"`.bak
mkdir -p /etc/yum.repos.d
cp "${PACKAGE_SOURCE_FILE_DIR}/${CENTOS_MIRROR_FILE_NAME}" /etc/yum.repos.d/${CENTOS_MIRROR_FILE_NAME}
sed -i "s|__BASE__|${COMMON_MIRROR_DIR}|g" /etc/yum.repos.d/${CENTOS_MIRROR_FILE_NAME}
yum clean all >> /dev/null 2>&1 && yum makecache >> /dev/null 2>&1

# Install containerd
echo -en "$GREEN_COL \tInstall containerd service ... $NORMAL_COL"
yum install -y containerd.io-${CONTAINERD_VERSION} >/dev/null 2>&1
systemctl restart containerd >/dev/null 2>&1
systemctl enable containerd >/dev/null 2>&1
echo -e "${YELLOW_COL} done ${NORMAL_COL}"

## TODO：Check containerd status

# Load images
CABIN_NGINX_IMAGE=`find ${PACKAGE_SOURCE_ROOT}/resources/images/save -name '*.tar.gz' -type f | xargs -I {} ctr i import {} | awk '{print $2}'`

# Start infra-nginx
if `ctr tasks ls | grep -Eqi ${PACKAGE_SOURCE_CONTAINERD_NAME}`; then
  ctr tasks kill ${PACKAGE_SOURCE_CONTAINERD_NAME} >> /dev/null 2>&1 || true
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

## Check package source package installation..
while true;do
  echo -e "$GREEN_COL Check offline source installation.. $NORMAL_COL"
  health_check=`curl -I -o /dev/null -s -w %{http_code}  http://localhost:3142/centos/7/repodata/repomd.xml`
  sleep 1
  if [ $health_check == 200 ];then
     echo -e "$GREEN_COL ... OK, will quit. $NORMAL_COL"
     exit 0
  else
    echo -e "$GREEN_COL ... Not OK, will retry, press ctrl-C to quit. $NORMAL_COL"
  fi
done
