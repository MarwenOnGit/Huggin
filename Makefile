# Huginn. Every target that changes Azure (apply, destroy, replay, evidence) asks
# Terraform or the script for confirmation; nothing here runs with -auto-approve.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

STACKS     ?= bootstrap sentinel lab
STACK      ?= sentinel
TF         := terraform
PY         := python3
RULE       ?=
OP         ?=

.PHONY: help init plan apply destroy fmt validate tflint checkov lint test replay evidence

help:
	@echo "make init|plan|apply STACK=bootstrap|sentinel|lab"
	@echo "make destroy            destroy lab, then sentinel (bootstrap kept; see docs/COST.md)"
	@echo "make lint               fmt check, validate, tflint, checkov"
	@echo "make test               static rule tests (no Azure)"
	@echo "make replay RULE=<id>   run one core rule's benign replay (asks first)"
	@echo "make evidence OP=<id>   Phase 3: capture AzureActivity rows for one operation"

init:
	$(TF) -chdir=infra/$(STACK) init

plan:
	$(TF) -chdir=infra/$(STACK) plan -out=tfplan

apply:
	$(TF) -chdir=infra/$(STACK) apply tfplan

destroy:
	$(TF) -chdir=infra/lab destroy
	$(TF) -chdir=infra/sentinel destroy

fmt:
	$(TF) fmt -check -recursive infra

validate:
	@for s in $(STACKS); do \
	  if ls infra/$$s/*.tf >/dev/null 2>&1; then \
	    $(TF) -chdir=infra/$$s init -backend=false -input=false >/dev/null && $(TF) -chdir=infra/$$s validate; \
	  fi; \
	done

tflint:
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"

checkov:
	checkov -d infra --framework terraform --quiet --compact

lint: fmt validate tflint checkov

test:
	$(PY) -m pytest -q tests/test_rules_static.py

replay:
	@test -n "$(RULE)" || (echo "usage: make replay RULE=<rule-id>" >&2; exit 2)
	@d=$$(ls -d detections/*/$(RULE)); test -x "$$d/replay.sh" || (echo "no replay.sh for $(RULE)" >&2; exit 2); \
	read -r -p "Run the benign replay for $(RULE) against the Huginn lab? [y/N] " a; [[ "$$a" == y ]]; \
	"$$d/replay.sh"

evidence:
	@test -n "$(OP)" || (echo "usage: make evidence OP=<op-id>" >&2; exit 2)
	@echo "Phase 3 evidence capture for $(OP) is not implemented yet." >&2; exit 2
