KUBE_VM ?= virtualbox
KUBE_CPU ?= 2
KUBE_MEM ?= 8192

.PHONY: help start clean new-client new-server start-all start-ingress \
  start-infra start-services print-hosts
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%20s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start-minikube: cmd-minikube ## Start minikube.
	@minikube ip 2>/dev/null || minikube start --vm-driver $(KUBE_VM) --cpus $(KUBE_CPU) --memory $(KUBE_MEM)

start-ota: start-all ## Start all infra and OTA+ services.

start: start-minikube start-ota ## Start minikube and all OTA+ services.

clean: cmd-minikube ## Delete minikube and all service data.
	@minikube delete >/dev/null || true
	@rm -rf generated/

new-client: %: start_%       ## Create a new client with a given name.
new-server: %: start_%       ## Create a new set of server credentials.
start-all: %: start_%        ## Start all infra and OTA+ services.
start-ingress: %: start_%    ## Install Nginx Ingress Controller
start-infra: %: start_%      ## Create infrastructure configs and apply to the cluster.
start-services: %: start_%   ## Start the OTA+ services.
print-hosts: %: start_%      ## Print the service mappings for /etc/hosts
templates: %: start_%        ## Generate all the k8s files

start_%: # Pass the target as an argument to start.sh
	@scripts/start.sh $*

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "${*}" first))
