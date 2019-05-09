.PHONY: help pull_images start_all start_weave start_ingress start_infra print_hosts \
  start_monitoring start_vaults start_services compress_logs delete_services delete_infra \
	compress_logs restart_all restart_vaults
.DEFAULT_GOAL := help

help: ## Print this message and exit
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%20s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start_all: %: start_%                 ## Apply infra and service configs to a new cluster.
start_weave: %: start_%               ## Install Weave Net.
start_ingress: %: start_%             ## Install Nginx Ingress Controller
start_infra: %: start_%               ## Create infrastructure configs and apply to the cluster.
start_services: %: start_%            ## Start the OTA+ services.
print_hosts: %: start_%               ## Print the service mappings for /etc/hosts
new_client: %: start_%                ## Provision new client via SSH
new_local_client: %: start_%          ## Provision new local client
delete_infra: %: start_%              ## helm delete the infra charts.
delete_services: %: start_%           ## helm delete the OTA+ services.

start_%: # Pass the target as an argument to start.sh
	@scripts/start.sh $*

docker_start_%: ## Start a local docker container.
	@scripts/docker_start.sh $*
