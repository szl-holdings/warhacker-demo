# SZL Warhacker demo — thin wrappers over scripts/. No magic: each target is a
# real script you can also run directly. See README "Quick start".
SHELL := bash
.DEFAULT_GOAL := help

.PHONY: help tower-verify bootstrap demo rehearse airgap-test thermal-guard

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

## tower-verify: full sovereign dry-run on this machine (air-gap-safe).
## Pre-flights the tower, then boots the k3d cluster + UDS bundle and prints the
## signed judge recipe. Needs an RTX-class GPU, Docker, and sudo (see README).
tower-verify: bootstrap demo ## Full dry-run: bootstrap_verify.sh then demo_run.sh

bootstrap: ## Pre-flight the tower (GPU/driver/docker/k3d/cosign + bundle verify)
	sudo bash scripts/bootstrap_verify.sh

demo: ## Boot the cluster, deploy the bundle, open the operator shell
	bash scripts/demo_run.sh

rehearse: ## No-cluster, no-GPU core proof: signed receipt chain + tamper test
	bash scripts/rehearse.sh

airgap-test: ## Prove the demo runs with zero outbound network (needs sudo)
	sudo bash scripts/airgap_test.sh

thermal-guard: ## Start the background GPU thermal daemon
	bash scripts/thermal_guard.sh
