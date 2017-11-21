CONFIG ?= config.yaml
SECRETS ?= secrets.yaml
GENERATED ?= .generated.yaml


.PHONY: help gen-config start-all
.DEFAULT_GOAL := help

help: ## Print this message and exit
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%15s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

cmd_%: # Check that a command exists
	@: $(if $(shell command -v ${*}),,$(error Please install "$*" first))

gen-config: cmd_kops ## Generate the config from templates
	@kops toolbox template \
		--values $(CONFIG) \
		--values $(SECRETS) \
		--template config \
		--logtostderr \
		--output $(GENERATED)
	@ed $(GENERATED) <<< $$'1d\nw' #FIXME: delete garbage first line

start-all: cmd_kubectl gen-config ## Start all services
	@kubectl apply --filename $(GENERATED)
