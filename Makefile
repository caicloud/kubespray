# Usage:
#   make convert-images  - convert images from download.yml into images list

# commitish
TAG = $(shell git describe --tags --always --dirty)

# RELEASE_VERSION is the version of the release
RELEASE_VERSION            ?= $(TAG)
RELEASE_TIME               ?= $(shell date +'%Y-%m-%d')

IMGAES_LIST_DIR            ?= ./images-lists
IMAGE_ARCH                 ?= amd64
DOWNLOAD_YAML_FILE         ?= ./inventory/deploy-cluster/group_vars/all/download.yml

# convert images in download.yml file to images list
convert-images:
	@mkdir -p $(IMGAES_LIST_DIR)
	@grep -Ev "^#|^$$|kubelet|kubeadm|---|\{%|%\}" $(DOWNLOAD_YAML_FILE) \
	| sed 's|{{ |$${|g;s| }}|}|g;s|: |=|g;s|"||g;s|image_arch=.*|image_arch=$(IMAGE_ARCH)|' > convert.sh
	@grep 'image_name=' convert.sh | awk -F "=" '{print $1}' | sed 's|^|$${|g;s|$$|}|g;s|^|echo |g' >> convert.sh
	@bash convert.sh | sed 's|^/||g' | grep -E '^release|^library' | sort -nr | uniq > $(IMGAES_LIST_DIR)/images_kubernetes.list
	@cat $(IMGAES_LIST_DIR)/images_kubernetes.list
	@rm -f convert.sh

.PHONY: convert-images

mitogen:
	ansible-playbook -c local mitogen.yml -vv
clean:
	rm -rf dist/
	rm *.retry
