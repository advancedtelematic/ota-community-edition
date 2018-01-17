CONFIG ?= config.yaml
OUTPUT ?= .generated.yaml
CA_DIR ?= ota.ce

KUBE_VM ?= virtualbox
KUBE_CPU ?= 2
KUBE_MEM ?= 8192


.PHONY: help start stop test clean start-all start-minikube start-services \
	create-databases unseal-vault copy-tokens print-hosts
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%16s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: start-all ## Start minikube and all services.

stop: cmd-minikube ## Stop minikube and all running services.
	@minikube stop

test: ## Run the end-to-end test suite.
	@false # FIXME: placeholder

clean: cmd-minikube ## Delete the minikube VM and all service data.
	@minikube delete >/dev/null || true
	@rm -rf $(CA_DIR)

start-all: \
	start-minikube \
	start-platform \
	start-vault \
	start-services

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment.
	@minikube ip 2>/dev/null || minikube start --vm-driver $(KUBE_VM) --cpus $(KUBE_CPU) --memory $(KUBE_MEM)
	@minikube addons enable ingress

start-services: cmd-kops ## Apply the generated config to the k8s cluster.
	@find templates/services -type f -not -name "*.yaml" -print \
    | xargs -I{} sh -c 'echo Non-template file found: {} && false'
	@kops toolbox template --template templates/services --values $(CONFIG) --output $(OUTPUT)
	@[ -d "$(CA_DIR)" ] || { \
		scripts/genserver.sh; \
		kubectl create secret generic gateway-tls \
		--from-file $(CA_DIR)/server.key \
		--from-file $(CA_DIR)/server.chain.pem \
		--from-file $(CA_DIR)/devices/ca.crt; \
		}
	@[ -f "$(OUTPUT)" ] && kubectl apply --filename $(OUTPUT)
	@scripts/container_run.sh wait_for_containers
	@scripts/container_run.sh init

start-platform: cmd-kops cmd-kubectl ## Create all database tables and users.
	@kubectl apply --filename templates/volumes.yaml
	@kops toolbox template --template templates/mysql.tmpl.yaml \
		--template templates/zookeeper.tmpl.yaml \
    --template templates/kafka.tmpl.yaml \
		--values $(CONFIG) --output .platform.yaml
	@kubectl apply --filename .platform.yaml
	@DB_PASS=$$(awk '/mysql_root_password/ {print $$2}' $(CONFIG)) \
		scripts/container_run.sh create-databases
	scripts/container_run.sh wait_for_containers

start-vault: cmd-minikube ## Automatically unseal the vault.
	@kops toolbox template --template templates/tuf-vault.tmpl.yaml --values $(CONFIG) --output .vault.yaml
	@kubectl apply --filename .vault.yaml
	@KEYSERVER_TOKEN=$$(awk '/tuf_keyserver_vault_token/ {print $$2}' $(CONFIG)) \
		scripts/container_run.sh unseal-vault

print-hosts: cmd-kubectl cmd-jq ## Print the service mappings for /etc/hosts
	@scripts/container_run.sh $@

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "${*}" first))
