CONFIG ?= config.yaml
OUTPUT ?= .generated.yaml

KUBE_VM ?= virtualbox
KUBE_CPU ?= 2
KUBE_MEM ?= 8192


.PHONY: help start stop delete start-all start-minikube start-services \
	create-databases unseal-vault copy-tokens hosts
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%16s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: start-all ## Start minikube and all services.

stop: cmd-minikube ## Stop minikube and all running services.
	@minikube stop

delete: cmd-minikube ## Delete the minikube VM and all service data.
	@minikube delete

start-all: \
	start-minikube \
	start-services \
	create-databases \
	unseal-vault \
	hosts

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment.
	@minikube ip 2>/dev/null || minikube start --vm-driver $(KUBE_VM) --cpus $(KUBE_CPU) --memory $(KUBE_MEM)
	@minikube addons enable ingress

start-services: cmd-kops ## Apply the generated config to the k8s cluster.
	@find templates -type f -not -name "*.yaml" -print \
		| xargs -I{} sh -c 'echo Non-template file found: {} && false'
	@kops toolbox template --template templates --values $(CONFIG) --output $(OUTPUT)
	@kubectl get secret gateway-tls 2>/dev/null || { \
		scripts/genserver.sh; \
		kubectl create secret generic gateway-tls \
		--from-file ota.ce/server.key \
		--from-file ota.ce/server.chain.pem \
		--from-file ota.ce/devices/ca.crt; \
		}
	@kubectl apply --filename $(OUTPUT)

create-databases: cmd-minikube ## Create all database tables and users.
	@DB_PASS=$$(awk '/mysql_root_password/ {print $$2}' $(CONFIG)) \
		scripts/container_run.sh $@

unseal-vault: cmd-minikube ## Automatically unseal the vault.
	@KEYSERVER_TOKEN=$$(awk '/tuf_keyserver_vault_token/ {print $$2}' $(CONFIG)) \
		scripts/container_run.sh $@

hosts: cmd-kubectl ## Print the service mappings for /etc/hosts
	@$(if $$(kubectl get ingress | egrep --quiet "(\d{1,3}.){3}\d{1,3}"), \
		kubectl get ingress --no-headers | awk '{print $$3 " " $$2}', \
		$(error Hosts are not ready yet))

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "${*}" first))
