################################################################################
## GLOBAL VARIABLES & GENERAL PURPOSE TARGETS
################################################################################

PROJECT_NAME := chore
PROJECT_DNS_NAME := chore
RUBY_VERSION := $$(cat .ruby-version)

SHELL := /bin/bash
MAKEFLAGS += --no-print-directory

# Tasks that interact w/ k8s should never be run in production. Localdev setups use the default kube config
# (~/.kube/config), whereas production kubeconfigs are kept in separate files.
KUBECONFIG :=

.PHONY: no-args
no-args:
# Do nothing by default. Ensure this is first in the list of tasks

.PHONY: print-%
print-%: ; @echo $($*)
# Use to print the evaluated value of a make variable. e.g. `make print-SHELL`

################################################################################
## DEVELOPMENT-RELATED TARGETS
################################################################################

.PHONY: dev-specs
dev-specs: devimage
	@docker run --rm -it \
		--volume ${PWD}:/project \
		${IMAGE_NAME}:devimage \
		bash -l -c "bundle install --path vendor/bundle --jobs 5 && bundle exec rspec"

.PHONY: devimage
devimage:
	@APP_USER_UID=$$(id -u) APP_USER_GID=$$(id -g) \
	IMAGE_TAG=devimage BUILD_TARGET=devimage \
	make baseimage

################################################################################
## CI/DOCKER-RELATED TARGETS
################################################################################

IMAGE_NAME := ${PROJECT_NAME}

# Cannot install Ruby 2.3.0 via RVM on later LTS releases (on ARM at least). Can update if/when Ruby version is updated.
ROOT_IMAGE := ubuntu:bionic

.PHONY: baseimage
baseimage: CACHE_DIR := .docker-build-cache
baseimage: IMAGE_TAG ?= baseimage
baseimage: DOCKER_BUILD_OPTS ?=
baseimage:
# The .docker-build-cache directory is a speed hack to avoid the Docker CLI unecessarily scanning the repo before build
	@mkdir -p ${CACHE_DIR}
	@cp Dockerfile ${CACHE_DIR}

	@docker build \
		 ${DOCKER_BUILD_OPTS} \
		--target baseimage \
		--build-arg ROOT_IMAGE=${ROOT_IMAGE} \
		--build-arg RUBY_VERSION=${RUBY_VERSION} \
		--tag ${IMAGE_NAME}:${IMAGE_TAG} \
		${CACHE_DIR}

	@rm -rf ${CACHE_DIR}
