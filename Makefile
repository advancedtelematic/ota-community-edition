CONFIG_FILE ?= config.yaml
IMAGES_FILE ?= images.yaml
SECRETS_FILE ?= secrets.yaml


.PHONY: help gen-config start-all
.DEFAULT_GOAL := help

help: ## Print this message and exit
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%15s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

cmd_%: # Check that a command exists
	@: $(if $(shell command -v ${*}),,$(error Please install "$*" first))

gen-config: cmd_kops ## Generate the config from templates
	@kops toolbox template \
		--values $(IMAGES_FILE) \
		--values $(SECRETS_FILE) \
		--template config \
		--logtostderr \
		--output $(CONFIG_FILE)
	@sed -i '' '1,/---/d' $(CONFIG_FILE) #FIXME: template returns garbage header lines?

start-all: cmd_kubectl gen-config ## Start all services
	@kubectl apply --filename $(CONFIG_FILE)
