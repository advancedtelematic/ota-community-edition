CONFIG ?= config.yaml
OUTPUT ?= .generated.yaml

KUBE_CPU ?= 2
KUBE_MEM ?= 8192


.PHONY: help start start-minikube start-servcies create-databases unseal-vault hosts
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%16s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: start-minikube start-services create-databases unseal-vault ## Start minikube and all services.

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment.
	@minikube ip 2>/dev/null || minikube start --cpus $(KUBE_CPU) --memory $(KUBE_MEM)
	@kubectl get secret docker-registry-key 2>/dev/null || \
		kubectl create secret docker-registry docker-registry-key \
			--docker-username=$(DOCKER_USER) \
			--docker-password=$(DOCKER_PASS) \
			--docker-email=$(DOCKER_EMAIL)
	@minikube addons enable ingress

start-services: cmd-kops ## Apply the generated config to the k8s cluster.
	@kops toolbox template --template templates --values $(CONFIG) --output $(OUTPUT)
	@sed '1,/^---/d' $(OUTPUT) > .temp && mv .temp $(OUTPUT)
	@kubectl apply --filename $(OUTPUT)

create-databases: cmd-kubectl ## Create all database tables and users.
	@eval $$(minikube docker-env); \
		until $$(docker ps | grep --silent mariadb); do sleep 5; done; sleep 15; \
		CONTAINER="$$(docker ps | grep mariadb | awk '{print $$1}')"; \
		docker cp scripts/create_databases.sql "$${CONTAINER}:/tmp"; \
		docker exec -it $${CONTAINER} bash -c "mysql -proot < /tmp/create_databases.sql"

unseal-vault: cmd-kubectl ## Automatically unseal the vault.
	@eval $$(minikube docker-env); \
		until $$(docker ps | grep --silent k8s_tuf-vault); do sleep 5; done; sleep 15; \
		CONTAINER="$$(docker ps | grep k8s_tuf-vault | awk '{print $$1}')"; \
		docker cp scripts/unseal_vault.sh "$${CONTAINER}:/tmp"; \
		docker exec $${CONTAINER} "/tmp/unseal_vault.sh"

hosts: cmd-kubectl ## Print the service mappings for /etc/hosts
	@kubectl get ingress | tail -n+2 | awk '{print $$3 " " $$2}'

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "$*" first))
