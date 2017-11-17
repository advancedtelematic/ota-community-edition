SERVICES ?= \
	device-registry \
	sota-core \
	campaigner \
	campaigner-daemon \
	director \
	director-daemon \
	treehub \
	web-events \
	tuf-keyserver \
	tuf-keyserver-daemon \
	tuf-reposerver \
	tuf-vault \
	device-gateway \
	app


.PHONY: help start-all
.DEFAULT_GOAL := help

help: ## Print this message and exit
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%10s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

cmd_%: # Check that a command exists
	@: $(if $(shell command -v ${*}),,$(error Command "$*" not found))

start-all: cmd_kubectl ## Start all services
	@$(foreach service,$(SERVICES), envsubst < "config/${service}.yaml" | kubectl apply --filename -;)
