#!/bin/bash
# Fix MongoDB probes for MongoDB 6.0+ (uses mongosh, not mongo)
oc patch statefulset aitp-mongodb-cluster -n aitp-data --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/exec/command", "value": ["mongosh", "--eval", "db.adminCommand(\"ping\")"]},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/exec/command", "value": ["mongosh", "--eval", "db.adminCommand(\"ping\")"]}
]'
oc delete pod -n aitp-data -l app=aitp-mongodb-cluster
