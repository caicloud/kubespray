# The old school Makefile, following are required targets. The Makefile is written
# to allow building multiple binaries. You are free to add more targets or change
# existing implementations, as long as the semantics are preserved.
#
#   make                 - default to 'build' target
#   make lint            - code analysis
#   make release-image   - build cluster-deploy-job image
#   make base-image      - build kubespray base image
#   $ docker login registry -u username -p xxxxx
#   make push            - push cluster-deploy-job image to registrys
#   make save            - save cluster-deploy-job image to xxx.tar.gz
#   make convert-images  - convert images from download.yml into images list
#
# Not included but recommended targets:
#   make e2e-test
#
# The makefile is also responsible to populate project version information.
#

#
# Tweak the variables based on your project.

# Module name.
NAME := cluster-deploy-job

# Container image prefix and suffix added to targets.
# The final built images are:
#   $[REGISTRY]/$[IMAGE_PREFIX]$[TARGET]$[IMAGE_SUFFIX]:$[VERSION]
# $[REGISTRY] is an item from $[REGISTRIES], $[TARGET] is an item from $[TARGETS].
IMAGE_PREFIX ?= $(strip )
IMAGE_SUFFIX ?= $(strip )

# Container registries.
REGISTRY ?= cargo.dev.caicloud.xyz/release

# Container registry for base images.
BASE_REGISTRY ?= cargo.caicloud.xyz/library

RELEASE_TIME               ?= $(shell date +'%Y-%m-%d')
IMGAES_LIST_DIR            ?= ./images-lists
IMAGE_ARCH                 ?= amd64
DOWNLOAD_YAML_FILE         ?= ./inventory/deploy-cluster/group_vars/all/download.yml
SAVE_PATH                  ?= /tmp
BASE_IMAGE_VERSION         ?= 18.04-kubespray-v0.1.0
KUBESPRAY_BASE_IMAGE       ?= $(BASE_REGISTRY)/ubuntu:$(BASE_IMAGE_VERSION)
KEEPALIVED_VERSION         ?= v0.1.0

#
# These variables should not need tweaking.
#

# It's necessary to set this because some environments don't link sh -> bash.
export SHELL := /bin/bash

# It's necessary to set the errexit flags for the bash shell.
export SHELLOPTS := errexit

IMAGE_NAME := $(IMAGE_PREFIX)$(NAME)$(IMAGE_SUFFIX)

# Current version of the project.
VERSION      ?= $(shell git describe --tags --always --dirty)
BRANCH       ?= $(shell git branch | grep \* | cut -d ' ' -f2)
GITCOMMIT    ?= $(shell git rev-parse HEAD)
GITTREESTATE ?= $(if $(shell git status --porcelain),dirty,clean)
BUILDDATE    ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Track code version with Docker Label.
DOCKER_LABELS ?= git-describe="$(shell date -u +v%Y%m%d)-$(shell git describe --tags --always --dirty)"

#
# Define all targets. At least the following commands are required:
#

# All targets.
.PHONY: lint release-image base-image push save

release-image:
	@sed -i- "s|KUBESPRAY_BASE_IMAGE|$(KUBESPRAY_BASE_IMAGE)|" build/cluster-deploy-job/Dockerfile
	@docker build --no-cache -t $(REGISTRY)/$(IMAGE_NAME):$(VERSION) \
	--label $(DOCKER_LABELS) -f build/cluster-deploy-job/Dockerfile .
	@mv -f build/cluster-deploy-job/Dockerfile- build/cluster-deploy-job/Dockerfile

base-image:
	@docker build --no-cache -t $(KUBESPRAY_BASE_IMAGE) \
	--label $(DOCKER_LABELS) -f build/kubespray-base-image/Dockerfile .

keepalived-image:
	@docker build --no-cache -t $(REGISTRY)/keepalived:$(KEEPALIVED_VERSION) \
	-f build/keepalived/Dockerfile .

push: release-image
	@docker push $(REGISTRY)/$(IMAGE_NAME):$(VERSION);

base-push: base-image
	@docker push $(KUBESPRAY_BASE_IMAGE)

keepalived-push: keepalived-image
	@docker push $(REGISTRY)/keepalived:$(KEEPALIVED_VERSION)

save: release-image
	@docker tag $(REGISTRY)/$(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(VERSION)
	@docker save -o $(SAVE_PATH)/$(IMAGE_NAME)-$(VERSION).tar $(IMAGE_NAME):$(VERSION)
	@gzip -f $(SAVE_PATH)/$(IMAGE_NAME)-$(VERSION).tar $(IMAGE_NAME):$(VERSION)

lint:
	@bash hack/lint/lint.sh

.PHONY: convert-images
# convert images in download.yml file to images list
convert-images:
	@mkdir -p $(IMGAES_LIST_DIR)
	@grep -Ev "^#|^$$|kubelet|kubeadm|---|\{%|%\}" $(DOWNLOAD_YAML_FILE) \
	| sed 's|{{ |$${|g;s| }}|}|g;s|: |=|g;s|"||g;s|image_arch=.*|image_arch=$(IMAGE_ARCH)|' > convert.sh
	@grep 'image_name=' convert.sh | awk -F "=" '{print $1}' | sed 's|^|$${|g;s|$$|}|g;s|^|echo |g' >> convert.sh
	@bash convert.sh | sed 's|^/||g' | grep -E '^release|^library' | sort -nr | uniq > $(IMGAES_LIST_DIR)/images_kubernetes.list
	@cat $(IMGAES_LIST_DIR)/images_kubernetes.list
	@rm -f convert.sh

.PHONY: mitogen clean
mitogen:
	ansible-playbook -c local mitogen.yml -vv
clean:
	rm -rf dist/
	rm *.retry
