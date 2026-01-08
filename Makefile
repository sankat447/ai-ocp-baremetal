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

clean:
	@echo "Cleaning up resources..."
	oc delete -f 07-ui-workflow/ --ignore-not-found
	oc delete -f 06-ai-stack/ --ignore-not-found
	oc delete -f 05-data-layer/ --ignore-not-found

# ============================================================================
# Phase 8: Virtualization (CNV + MTV)
# ============================================================================

virtualization: cnv-operator cnv-deploy mtv-operator mtv-deploy vm-templates
	@echo -e "$(GREEN)=== Virtualization Layer Complete ===$(NC)"

# --- CNV (OpenShift Virtualization) ---

cnv-operator:
	@echo -e "$(GREEN)=== Installing OpenShift Virtualization Operator ===$(NC)"
	oc apply -f 08-virtualization/operators/cnv-namespace.yaml
	oc apply -f 08-virtualization/operators/cnv-operatorgroup.yaml
	oc apply -f 08-virtualization/operators/cnv-subscription.yaml
	@echo "Waiting for CNV operator to be ready..."
	@sleep 60
	@until oc get csv -n openshift-cnv 2>/dev/null | grep -q "kubevirt-hyperconverged-operator.*Succeeded"; do \
		echo "Waiting for CNV operator CSV..."; \
		sleep 30; \
	done
	@echo -e "$(GREEN)CNV Operator installed successfully$(NC)"

cnv-deploy:
	@echo -e "$(GREEN)=== Deploying HyperConverged CR ===$(NC)"
	oc apply -f 08-virtualization/operators/cnv-hyperconverged.yaml
	@echo "Waiting for CNV deployment (this may take 10-15 minutes)..."
	@until oc get hco kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q "True"; do \
		echo "Waiting for HyperConverged to be Available..."; \
		sleep 60; \
	done
	@echo -e "$(GREEN)OpenShift Virtualization deployed successfully$(NC)"

# --- MTV (Migration Toolkit for Virtualization) ---

mtv-operator:
	@echo -e "$(GREEN)=== Installing MTV Operator ===$(NC)"
	oc apply -f 08-virtualization/mtv/mtv-namespace.yaml
	oc apply -f 08-virtualization/mtv/mtv-operatorgroup.yaml
	oc apply -f 08-virtualization/mtv/mtv-subscription.yaml
	@echo "Waiting for MTV operator to be ready..."
	@sleep 60
	@until oc get csv -n openshift-mtv 2>/dev/null | grep -q "mtv-operator.*Succeeded"; do \
		echo "Waiting for MTV operator CSV..."; \
		sleep 30; \
	done
	@echo -e "$(GREEN)MTV Operator installed successfully$(NC)"

mtv-deploy:
	@echo -e "$(GREEN)=== Deploying ForkliftController ===$(NC)"
	oc apply -f 08-virtualization/mtv/mtv-forkliftcontroller.yaml
	@echo "Waiting for Forklift deployment..."
	@sleep 120
	@until oc get forkliftcontroller forklift-controller -n openshift-mtv -o jsonpath='{.status.conditions[?(@.type=="Successful")].status}' 2>/dev/null | grep -q "True"; do \
		echo "Waiting for ForkliftController to be ready..."; \
		sleep 30; \
	done
	@echo -e "$(GREEN)MTV deployed successfully$(NC)"

# --- VM Templates ---

vm-templates:
	@echo -e "$(GREEN)=== Creating VM Templates and Namespace ===$(NC)"
	oc apply -f 08-virtualization/templates/vm-namespace.yaml
	oc apply -f 08-virtualization/templates/datavolumes-os-images.yaml || true
	oc apply -f 08-virtualization/templates/vm-templates.yaml || true
	@echo -e "$(GREEN)VM templates created$(NC)"

vm-examples:
	@echo -e "$(GREEN)=== Deploying Example VMs ===$(NC)"
	oc apply -f 08-virtualization/vm-examples/example-vms.yaml
	@echo -e "$(GREEN)Example VMs deployed$(NC)"

# ============================================================================
# VM Management Targets
# ============================================================================

vm-list:
	@echo -e "$(GREEN)=== Virtual Machines ===$(NC)"
	oc get vm -A

vm-status:
	@echo -e "$(GREEN)=== VM Status ===$(NC)"
	oc get vmi -A

vm-start:
	@test -n "$(VM)" || (echo "Usage: make vm-start VM=<name> NS=<namespace>"; exit 1)
	@NS=$${NS:-aitp-vms}; \
	oc patch vm $(VM) -n $$NS --type merge -p '{"spec":{"running":true}}'
	@echo "VM $(VM) started"

vm-stop:
	@test -n "$(VM)" || (echo "Usage: make vm-stop VM=<name> NS=<namespace>"; exit 1)
	@NS=$${NS:-aitp-vms}; \
	oc patch vm $(VM) -n $$NS --type merge -p '{"spec":{"running":false}}'
	@echo "VM $(VM) stopped"

vm-console:
	@test -n "$(VM)" || (echo "Usage: make vm-console VM=<name> NS=<namespace>"; exit 1)
	@NS=$${NS:-aitp-vms}; \
	virtctl console $(VM) -n $$NS

vm-ssh:
	@test -n "$(VM)" || (echo "Usage: make vm-ssh VM=<name> NS=<namespace> USER=<user>"; exit 1)
	@NS=$${NS:-aitp-vms}; \
	USER=$${USER:-cloud-user}; \
	virtctl ssh $$USER@$(VM) -n $$NS

# ============================================================================
# Utility Targets
# ============================================================================

validate:
	@echo -e "$(GREEN)=== Validating Configuration ===$(NC)"
	@echo "Checking CNV..."
	oc get hco kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
	@echo ""
	@echo "Checking MTV..."
	oc get forkliftcontroller forklift-controller -n openshift-mtv -o jsonpath='{.status.conditions[?(@.type=="Successful")].status}'
	@echo ""
	@echo "Checking VMs..."
	oc get vm -A
	@echo -e "$(GREEN)=== Validation Complete ===$(NC)"

status:
	@echo -e "$(GREEN)=== Cluster Status ===$(NC)"
	@echo ""
	@echo "=== Nodes ==="
	oc get nodes
	@echo ""
	@echo "=== CNV Status ==="
	oc get hco -n openshift-cnv || echo "CNV not installed"
	@echo ""
	@echo "=== MTV Status ==="
	oc get forkliftcontroller -n openshift-mtv || echo "MTV not installed"
	@echo ""
	@echo "=== Virtual Machines ==="
	oc get vm -A || echo "No VMs found"
	@echo ""
	@echo "=== Running VMIs ==="
	oc get vmi -A || echo "No VMIs running"

clean-vms:
	@echo -e "$(YELLOW)=== Cleaning up VMs ===$(NC)"
	oc delete vm --all -n aitp-vms || true
	oc delete pvc --all -n aitp-vms || true
	@echo -e "$(GREEN)VMs cleaned up$(NC)"

clean-virtualization:
	@echo -e "$(RED)=== Removing Virtualization Layer ===$(NC)"
	oc delete forkliftcontroller forklift-controller -n openshift-mtv || true
	oc delete hco kubevirt-hyperconverged -n openshift-cnv || true
	@sleep 120
	oc delete subscription mtv-operator -n openshift-mtv || true
	oc delete subscription kubevirt-hyperconverged -n openshift-cnv || true
	oc delete csv -n openshift-mtv --all || true
	oc delete csv -n openshift-cnv --all || true
	oc delete namespace openshift-mtv || true
	oc delete namespace openshift-cnv || true
	@echo -e "$(GREEN)Virtualization layer removed$(NC)"

help:
	@echo "AITP Stack Makefile"
	@echo ""
	@echo "Main Targets:"
	@echo "  all                - Deploy complete stack"
	@echo "  virtualization     - Deploy CNV + MTV"
	@echo "  validate           - Validate deployment"
	@echo "  status             - Show cluster status"
	@echo ""
	@echo "Virtualization Targets:"
	@echo "  cnv-operator       - Install CNV operator"
	@echo "  cnv-deploy         - Deploy HyperConverged"
	@echo "  mtv-operator       - Install MTV operator"
	@echo "  mtv-deploy         - Deploy ForkliftController"
	@echo "  vm-templates       - Create VM templates"
	@echo "  vm-examples        - Deploy example VMs"
	@echo ""
	@echo "VM Management:"
	@echo "  vm-list            - List all VMs"
	@echo "  vm-status          - Show VMI status"
	@echo "  vm-start VM=name   - Start a VM"
	@echo "  vm-stop VM=name    - Stop a VM"
	@echo "  vm-console VM=name - Access VM console"
	@echo "  vm-ssh VM=name     - SSH into VM"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean-vms          - Delete all VMs"
	@echo "  clean-virtualization - Remove CNV + MTV"