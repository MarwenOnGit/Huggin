# Huginn. Every target that changes Azure (apply, destroy, replay, evidence) asks
# Terraform or the script for confirmation; nothing here runs with -auto-approve.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

STACKS     ?= bootstrap sentinel lab purple
STACK      ?= sentinel
TF         := terraform
PY         := python3
RULE       ?=
OP         ?=
comma      := ,

.PHONY: help init plan apply destroy purple-destroy purple-preflight purple-capture fmt validate tflint checkov lint test kql ci replay evidence

help:
	@echo "make init|plan|apply STACK=bootstrap|sentinel|lab|purple"
	@echo "make destroy            destroy purple (if initialised), lab, then sentinel (bootstrap kept; see docs/COST.md)"
	@echo "make purple-destroy     destroy the purple-team environment right after a run (docs/PURPLE-TEAM.md)"
	@echo "make purple-preflight   after apply: diagnostic settings present and data reaching the workspace"
	@echo "make purple-capture SINCE=<utc> LABEL=<name> IND=<id,ip,...>   every table the run touched"
	@echo "make lint               fmt check, validate, tflint, checkov"
	@echo "make test               static rule tests (no Azure)"
	@echo "make kql                KQL syntax check with Kusto.Language (needs the .NET SDK)"
	@echo "make ci                 what ci.yml runs: test, kql, lint"
	@echo "make replay RULE=<id>   run one core rule's benign replay (asks first)"
	@echo "make evidence OP=<ids>  benign evidence actions as the signed-in az identity (asks first)"
	@echo "                        OP is comma-separated: X-08, X-13, X-13-fail, P-12"

init:
	@if [ "$(STACK)" = bootstrap ]; then \
	  $(TF) -chdir=infra/bootstrap init; \
	else \
	  test -f infra/shared/backend.hcl || (echo "apply infra/bootstrap first" >&2; exit 2); \
	  $(TF) -chdir=infra/$(STACK) init -backend-config=../shared/backend.hcl -backend-config=key=$(STACK).tfstate; \
	fi

plan:
	$(TF) -chdir=infra/$(STACK) plan -out=tfplan

apply:
	$(TF) -chdir=infra/$(STACK) apply tfplan

destroy:
	@if [ -d infra/purple/.terraform ]; then $(TF) -chdir=infra/purple destroy; fi
	$(TF) -chdir=infra/lab destroy
	$(TF) -chdir=infra/sentinel destroy
	@echo "infra/bootstrap is kept (state storage + identities, ~0 cost). To remove it too:"
	@echo "  terraform -chdir=infra/bootstrap destroy"

purple-destroy:
	$(TF) -chdir=infra/purple destroy

purple-preflight:
	$(PY) scripts/purple/preflight.py

purple-capture:
	@test -n "$(SINCE)" -a -n "$(LABEL)" || (echo "usage: make purple-capture SINCE=<utc> LABEL=<name> [UNTIL=<utc>] [IND=a,b]" >&2; exit 2)
	$(PY) scripts/purple/capture.py --since "$(SINCE)" --label "$(LABEL)" $(if $(UNTIL),--until "$(UNTIL)") \
	  $(foreach i,$(subst $(comma), ,$(IND)),--indicator "$(i)")

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
	checkov -d infra --config-file .checkov.yaml
	checkov -d infra/lab --config-file .checkov.yaml --var-file tests/checkov/optin-all.tfvars

lint: fmt validate tflint checkov

test:
	$(PY) -m pytest -q tests/test_rules_static.py

kql:
	dotnet run --project tests/kql_check -- "$(CURDIR)"
	dotnet run --no-build --project tests/kql_check -- --expect-errors "$(CURDIR)/tests/kql_check/fixtures/broken"

ci: test kql lint

replay:
	@test -n "$(RULE)" || (echo "usage: make replay RULE=<rule-id>" >&2; exit 2)
	@d=$$(ls -d detections/*/$(RULE)); test -x "$$d/replay.sh" || (echo "no replay.sh for $(RULE)" >&2; exit 2); \
	read -r -p "Run the benign replay for $(RULE) against the Huginn lab? [y/N] " a; [[ "$$a" == y ]]; \
	"$$d/replay.sh"

evidence:
	@test -n "$(OP)" || (echo "usage: make evidence OP=<op-id>[,<op-id>...]" >&2; exit 2)
	@echo "Azure CLI identity: $$(az account show --query user.name -o tsv)"
	@read -r -p "Run the benign evidence actions $(OP) against the Huginn lab? [y/N] " a; [[ "$$a" == y ]]; \
	started=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	scripts/evidence/run.sh "$(OP)"; \
	echo "Done. After ingestion (3 to 10 minutes), capture the rows with:"; \
	echo "  $(PY) scripts/evidence/capture.py --since $$started"
