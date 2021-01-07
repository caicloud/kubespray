#!/bin/sh
#
# The script sync all images which in the *.list files
# pull from SOURCE_REGISTRY and push to TARGET_REGISTRY
# see usage function for how to run.
#
# script/
# └── sync_images_scripts
#     └── sync.sh

function usage {
  echo -e "Usage:"
  echo -e " bash sync.sh [SOURCE_REGISTRY] [TARGET_REGISTRY] [IMAGE_LISTS_PATH]"
  echo -e ""
  echo -e " The script sync all images which in the *.list files"
  echo -e " pull from SOURCE_REGISTRY and push to TARGET_REGISTRY"
  echo -e ""
  echo -e "Parameter:"
  echo -e " SOURCE_REGISTRY\tpull images from this registry."
  echo -e " TARGET_REGISTRY\tpush images to this registry."
  echo -e " IMAGE_LISTS_PATH\tpath of images lists to sync."
  echo -e ""
  echo -e "Example:"
  echo -e " bash sync.sh cargo.caicloud.xyz harbor.caicloud.xyz ./oem-images-lists"
}

# -----------------------------------------------------------------------------
# Parameters for syncing docker images, see usage.
# -----------------------------------------------------------------------------
#
SOURCE_REGISTRY=$1
TARGET_REGISTRY=$2
IMAGE_LISTS_PATH=$3
IMAGE_LISTS_PATH=${IMAGE_LISTS_PATH:=`pwd`}
IMAGE_LISTS_SUFFIX=".list"

GREEN_COL="\\033[32;1m"         # green color
RED_COL="\\033[1;31m"           # red color
NORMAL_COL="\\033[0;39m"

# print the usage.
if [[ "$#" == "1" ]]; then
  if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
  fi
fi

cd ${IMAGE_LISTS_PATH}

IMAGE_LISTS=$( ls | grep "${IMAGE_LISTS_SUFFIX}" | xargs )

echo -e "$GREEN_COL Got image lists ${IMAGE_LISTS} $NORMAL_COL"

for IMAGE_LIST_FILE in ${IMAGE_LISTS[@]}
do
    echo -e "$GREEN_COL handling file ${IMAGE_LIST_FILE} $NORMAL_COL"
    for line in `cat ${IMAGE_LIST_FILE} | grep -v ^# | grep -v ^$`
    do
        # get IMAGE_PROJECT and IMAGE_NAME from image.list
        SOURCE_PROJECT=`echo $line | cut -d \/ -f 1`
        IMAGE_NAME=`echo $line | cut -d \/ -f 2`
        case $SOURCE_PROJECT in
          "release" )
            # if SOURCE_REGISTRY is cargo.caicloud.xyz, change release project into devops_release， just for pulling images
            if [ $SOURCE_REGISTRY = "cargo.caicloud.xyz" ] ; then
                line=`echo $line | sed 's/release\//devops_release\//g'`
            fi
        esac
        # push to same project
        TARGET_PROJECT=${SOURCE_PROJECT}
        NEW_IMAGE=${TARGET_REGISTRY}/${TARGET_PROJECT}/${IMAGE_NAME}
        # pull images
        docker pull ${SOURCE_REGISTRY}/${line}
        if [[ $? != 0 ]]; then
            echo -e "$RED_COL Pull image ${SOURCE_REGISTRY}/${line} error... $NORMAL_COL"
            echo ${SOURCE_REGISTRY}/$line >> miss_image.txt
        else
        echo -e "$GREEN_COL ${SOURCE_REGISTRY}/${line} successfully pulled $NORMAL_COL"
        fi
        docker tag ${SOURCE_REGISTRY}/$line $NEW_IMAGE

        # push images
        docker push $NEW_IMAGE
        if [[ $? != 0 ]]; then
            echo -e "$RED_COL Push image ${NEW_IMAGE} error... $NORMAL_COL"
            echo "${NEW_IMAGE}" >> miss_push_image.txt
        else
        echo -e "$GREEN_COL ${NEW_IMAGE} successfully pushed $NORMAL_COL"
        fi
    done
done
