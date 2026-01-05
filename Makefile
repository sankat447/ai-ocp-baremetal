.PHONY: all prerequisites install-ocp post-install gitops operators data-layer ai-stack ui-workflow

SHELL := /bin/bash

# Main deployment target
all: prerequisites install-ocp post-install gitops operators data-layer ai-stack ui-workflow
	@echo "AITP Stack deployment complete!"

# Phase 0: Prerequisites
prerequisites:
	@echo "=== Phase 0: Prerequisites ==="
	./00-prerequisites/idrac-setup.sh
	@echo "Configure DNS and switch settings manually"
	@read -p "Press enter when DNS and network are ready..."

# Phase 1: OCP Installation
install-ocp:
	@echo "=== Phase 1: OCP Installation ==="
	cd 01-ocp-install && ./scripts/install.sh
	@echo "Waiting for cluster to be ready..."
	sleep 60
	export KUBECONFIG=01-ocp-install/scripts/cluster-install/auth/kubeconfig && \
	oc wait --for=condition=Available clusterversion/version --timeout=30m

# Phase 2: Post-Install
post-install:
	@echo "=== Phase 2: Post-Install Configuration ==="
	oc apply -f 02-post-install/schedulable-masters.yaml
	oc apply -f 02-post-install/storage-class/local-storage.yaml
	@echo "Waiting for local storage operator..."
	sleep 120
	oc apply -f 02-post-install/network-policies/

# Phase 3: GitOps Bootstrap
gitops:
	@echo "=== Phase 3: GitOps Bootstrap ==="
	oc apply -f 03-gitops-bootstrap/argocd/operator.yaml
	@echo "Waiting for GitOps operator..."
	sleep 120
	oc wait --for=condition=Ready pod -l app.kubernetes.io/name=openshift-gitops-server -n openshift-gitops --timeout=5m
	oc apply -f 03-gitops-bootstrap/argocd/argocd-instance.yaml
	sleep 60
	oc apply -f 03-gitops-bootstrap/app-of-apps/

# Phase 4: Operators
operators:
	@echo "=== Phase 4: Operators Installation ==="
	oc apply -f 04-operators/odf-operator/subscription.yaml
	sleep 30
	oc apply -f 04-operators/postgresql-operator/
	oc apply -f 04-operators/mongodb-operator/
	oc apply -f 04-operators/redis-operator/
	oc apply -f 04-operators/acs-operator/
	oc apply -f 04-operators/sso-operator/
	oc apply -f 04-operators/servicemesh-operator/
	@echo "Waiting for operators..."
	sleep 300
	oc apply -f 04-operators/odf-operator/storagecluster.yaml
	@echo "Waiting for ODF storage cluster..."
	sleep 600

# Phase 5: Data Layer
data-layer:
	@echo "=== Phase 5: Data Layer ==="
	oc apply -f 05-data-layer/namespaces.yaml
	oc apply -f 05-data-layer/postgresql/
	oc apply -f 05-data-layer/mongodb/
	oc apply -f 05-data-layer/redis/
	oc apply -f 05-data-layer/clickhouse/
	oc apply -f 05-data-layer/meilisearch/
	@echo "Waiting for data services..."
	sleep 300

# Phase 6: AI Stack
ai-stack:
	@echo "=== Phase 6: AI Stack ==="
	oc apply -f 06-ai-stack/portkey/
	oc apply -f 06-ai-stack/langserve/
	oc apply -f 06-ai-stack/langgraph/
	@echo "Waiting for AI services..."
	sleep 120

# Phase 7: UI & Workflow
ui-workflow:
	@echo "=== Phase 7: UI & Workflow ==="
	oc apply -f 07-ui-workflow/librechat/
	oc apply -f 07-ui-workflow/n8n/
	@echo "Waiting for UI services..."
	sleep 60

# Utility targets
status:
	@echo "=== Cluster Status ==="
	oc get nodes
	oc get co
	@echo "=== Storage Status ==="
	oc get pv,pvc -A
	@echo "=== Pods Status ==="
	oc get pods -n aitp-data
	oc get pods -n aitp-ai
	oc get pods -n aitp-ui

routes:
	@echo "=== Application Routes ==="
	oc get routes -A | grep -E "aitp|console"

clean:
	@echo "Cleaning up resources..."
	oc delete -f 07-ui-workflow/ --ignore-not-found
	oc delete -f 06-ai-stack/ --ignore-not-found
	oc delete -f 05-data-layer/ --ignore-not-found
