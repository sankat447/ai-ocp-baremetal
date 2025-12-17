#!/bin/bash
BACKUP_DIR="./secrets-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

for ns in aitp-data aitp-ai aitp-ui; do
  echo "Backing up secrets from $ns..."
  oc get secrets -n $ns -o yaml > "$BACKUP_DIR/$ns-secrets.yaml"
done

echo "Secrets backed up to $BACKUP_DIR"
