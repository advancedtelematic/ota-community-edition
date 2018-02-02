KUBECTL ?= kubectl
KUBE_VM ?= virtualbox
KUBE_CPU ?= 2
KUBE_MEM ?= 8192

GEN_PLATFORM ?= .platform.yaml
GEN_VAULT ?= .vault.yaml
GEN_SERVICES ?= .services.yaml

CA_DIR ?= ota.ce
CONFIG ?= config.yaml
DB_PASS = $$(awk '/mysql_root_password/ {print $$2}' $(CONFIG))
DNS_NAME = $$(awk '/ingress_dns_name/ {print $$2}' $(CONFIG))
KS_TOKEN = $$(awk '/tuf_keyserver_vault_token/ {print $$2}' $(CONFIG))


.PHONY: help start stop test clean start-all generate-templates \
	start-minikube start-platform unseal-vault start-services print-hosts
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%20s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: start-all ## Start minikube and all services.

stop: cmd-minikube ## Stop minikube and all running services.
	@minikube stop

test: ## Run the end-to-end test suite.
	@false # FIXME: placeholder

clean: cmd-minikube ## Delete the minikube VM and all service data.
	@minikube delete >/dev/null || true
	@rm -rf $(CA_DIR)

start-all: \
	generate-templates \
	start-minikube \
	start-helm \
	start-platform \
	unseal-vault \
	start-services

generate-templates: cmd-kops ## Generate kubernetes config from the templates.
	@find templates -type f -not -name "*.yaml" -print \
		| xargs -I{} sh -c 'echo Non-template file found: {} && false'
	@kops toolbox template --template templates/platform --values $(CONFIG) --output $(GEN_PLATFORM)
	@kops toolbox template --template templates/vault --values $(CONFIG) --output $(GEN_VAULT)
	@kops toolbox template --template templates/services --values $(CONFIG) --output $(GEN_SERVICES)

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment.
	@minikube ip 2>/dev/null || \
		minikube start --vm-driver $(KUBE_VM) --cpus $(KUBE_CPU) --memory $(KUBE_MEM)
	@minikube addons enable ingress

start-helm:
	@scripts/helm_install.sh
	@helm init

start-platform: cmd-kubectl ## Create all database tables and users.
	@[ -d "$(CA_DIR)" ] || { \
		scripts/genserver.sh; \
		$(KUBECTL) create secret generic gateway-tls \
		--from-file $(CA_DIR)/server.key \
		--from-file $(CA_DIR)/server.chain.pem \
		--from-file $(CA_DIR)/devices/ca.crt; \
	}
	@$(KUBECTL) apply --filename $(GEN_PLATFORM)
	@DB_PASS=$(DB_PASS) scripts/container_run.sh create-databases
	minikube ssh -- "for dir in mysql treehub kafka zookeeper; do \
			 sudo mkdir -p /data/\$${dir}-pv-1; sudo chmod 777 /data/\$${dir}-pv-1; done"

unseal-vault: cmd-kubectl cmd-http cmd-jq ## Automatically unseal vault.
	@$(KUBECTL) apply --filename $(GEN_VAULT)
	@DNS_NAME=$(DNS_NAME) KEYSERVER_TOKEN=$(KS_TOKEN) scripts/container_run.sh $@

start-services: cmd-kubectl cmd-http cmd-jq ## Start the OTA services.
	@$(KUBECTL) apply --filename $(GEN_SERVICES)
	@DNS_NAME=$(DNS_NAME) scripts/container_run.sh $@

print-hosts: cmd-kubectl cmd-jq ## Print the service mappings for /etc/hosts
	@scripts/container_run.sh $@

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "${*}" first))
