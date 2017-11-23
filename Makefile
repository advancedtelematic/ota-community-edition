CONFIG ?= config.yaml
SECRETS ?= secrets.yaml
GENERATED ?= .generated.yaml

K8S_VERSION = $(shell kubectl version | base64 | tr -d '\n')


.PHONY: help gen-config start-minikube start-services
.DEFAULT_GOAL := help

help: ## Print this message and exit
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%15s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

cmd-%: # Check that a command exists
	@: $(if $(shell command -v ${*} 2>/dev/null),,$(error Please install "$*" first))

gen-config: cmd-kops ## Generate the config from templates
	@kops toolbox template \
		--values $(CONFIG) \
		--values $(SECRETS) \
		--template templates \
		--logtostderr \
		--output $(GENERATED)
	@ed $(GENERATED) <<< $$'1d\nw' #FIXME: delete garbage first line
	@cat configs/ingress.yaml >> $(GENERATED)

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment
	@minikube start --memory 10000 --network-plugin=cni
	@kubectl apply --filename "https://cloud.weave.works/k8s/net?k8s-version=$(K8S_VERSION)"

start-services: cmd-kubectl gen-config ## Start all services
	@kubectl apply --filename $(GENERATED)
