#!/bin/bash
echo "=== AI Cluster (ocp419) Validation ==="

echo ""
echo "Nodes:"
oc get nodes

echo ""
echo "Cluster Operators:"
oc get co | grep -v "True.*False.*False"

echo ""
echo "Storage:"
oc get pv,pvc -A | head -20

echo ""
echo "Pods (non-running):"
oc get pods -A | grep -v Running | grep -v Completed

echo ""
echo "Routes:"
oc get routes -A | grep -E "aitp|console|gitops"

echo ""
echo "=== Validation Complete ==="
