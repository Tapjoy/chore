########################################################################################################################
## GLOBAL VARIABLES & GENERAL PURPOSE TARGETS
########################################################################################################################

PROJECT_NAME := chore

SHELL := /bin/bash
MAKEFLAGS += --no-print-directory

IMAGE_TAG ?= baseimage
BUNDLE_GEMFILE ?= Gemfile.latest

.PHONY: no-args
no-args:
# Do nothing by default. Ensure this is first in the list of tasks

.PHONY: print-%
print-%: ; @echo $($*)
# Use to print the evaluated value of a make variable. e.g. `make print-SHELL`

.PHONY: deps
deps: SHELL := ${SHELL} -l
deps:
	bundle config set --local path vendor/bundle
	bundle install --jobs $$(getconf _NPROCESSORS_ONLN)

.PHONY: test
test: SHELL := ${SHELL} -l
test:
	bundle exec rspec ${TEST}

########################################################################################################################
## CI & DOCKER RELATED TARGETS
########################################################################################################################

REGISTRY := localhost:5000/tapjoy
GIT_SHA := $$(git rev-parse HEAD)
IMAGE_NAME := ${REGISTRY}/${PROJECT_NAME}
ROOT_IMAGE := ubuntu:bionic

.PHONY: baseimage
baseimage: CACHE_DIR := .docker-build-cache
baseimage: DOCKER_BUILD_OPTS ?=
baseimage: export BUNDLE_GEMFILE ?= ${BUNDLE_GEMFILE}
baseimage: export IMAGE_TAG ?= ${IMAGE_TAG}
baseimage:
# The .docker-build-cache directory is a speed hack to avoid the Docker CLI unecessarily scanning the repo before build
	@mkdir -p ${CACHE_DIR}
	@cp Dockerfile ${CACHE_DIR}
	@cp ${BUNDLE_GEMFILE}.lock ${CACHE_DIR}/Gemfile.lock

	docker build \
		 ${DOCKER_BUILD_OPTS} \
		--target baseimage \
		--build-arg ROOT_IMAGE=${ROOT_IMAGE} \
		--tag $$(make baseimage-tag) \
		${CACHE_DIR}

	@rm -rf ${CACHE_DIR}

.PHONY: baseimage-tag
baseimage-tag: IMAGE_TAG ?= baseimage
baseimage-tag: BUNDLE_GEMFILE ?= Gemfile.latest
baseimage-tag:
	@echo ${IMAGE_NAME}:${IMAGE_TAG}-ruby$$(grep -A 1 'RUBY VERSION' ${BUNDLE_GEMFILE}.lock | tail -n 1 | sed 's/ruby//' | awk '{$$1=$$1};1' | grep -oE '^[0-9\.]+')

.PHONY: baseimage-inspect
baseimage-inspect: export BUNDLE_GEMFILE ?= ${BUNDLE_GEMFILE}
baseimage-inspect: export IMAGE_TAG ?= ${IMAGE_TAG}
baseimage-inspect: baseimage
	docker run \
		-it \
		--volume $$(pwd):/project \
		--add-host host.docker.internal:host-gateway \
		--env BUNDLE_GEMFILE \
		$$(make baseimage-tag) \
		bash -l

.PHONY: ci
ci: RECIPE ?= ci-test
ci: export BUNDLE_GEMFILE ?= ${BUNDLE_GEMFILE}
ci: export IMAGE_TAG ?= ${IMAGE_TAG}
ci:
	docker run \
		--volume $$(pwd):/project \
		--add-host host.docker.internal:host-gateway \
		--env BUNDLE_GEMFILE \
		$$(make baseimage-tag) \
		make ${RECIPE}

.PHONY: ci-test
ci-test: deps test

.PHONY: ci-all
ci-all:
	for gemfile_name in $$(ls Gemfile* | grep -Ev lock); do \
		BUNDLE_GEMFILE=$${gemfile_name} make baseimage ci;\
	done
