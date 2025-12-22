#!/bin/bash
# setup-credentials.sh
# This script helps you configure install-config.yaml with proper credentials

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

INSTALL_CONFIG="install-config.yaml"

echo "=============================================="
echo "  AITP Lab - Credentials Setup Script"
echo "=============================================="
echo ""

# ============================================
# STEP 1: SSH Key
# ============================================
log_step "1/3 - Setting up SSH Key"

SSH_KEY=""

# Check for existing SSH keys
if [ -f ~/.ssh/id_rsa.pub ]; then
    SSH_KEY_FILE=~/.ssh/id_rsa.pub
    log_info "Found existing SSH key: ${SSH_KEY_FILE}"
elif [ -f ~/.ssh/id_ed25519.pub ]; then
    SSH_KEY_FILE=~/.ssh/id_ed25519.pub
    log_info "Found existing SSH key: ${SSH_KEY_FILE}"
else
    log_warn "No SSH key found. Generating new key pair..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "aitp-lab-admin"
    SSH_KEY_FILE=~/.ssh/id_ed25519.pub
    log_info "Generated new SSH key: ${SSH_KEY_FILE}"
fi

SSH_KEY=$(cat "${SSH_KEY_FILE}")
log_info "SSH Key (first 50 chars): ${SSH_KEY:0:50}..."
echo ""

# ============================================
# STEP 2: Pull Secret
# ============================================
log_step "2/3 - Setting up Pull Secret"

echo ""
echo "You need a Red Hat pull secret to install OpenShift."
echo ""
echo "  1. Go to: ${BLUE}https://console.redhat.com/openshift/install/pull-secret${NC}"
echo "  2. Log in with your Red Hat account (free account works)"
echo "  3. Click 'Download' or 'Copy' to get your pull secret"
echo ""

PULL_SECRET=""

# Check if pull-secret.json exists
if [ -f "pull-secret.json" ]; then
    log_info "Found pull-secret.json file"
    PULL_SECRET=$(cat pull-secret.json | tr -d '\n' | tr -d ' ')
elif [ -f "pull-secret.txt" ]; then
    log_info "Found pull-secret.txt file"
    PULL_SECRET=$(cat pull-secret.txt | tr -d '\n' | tr -d ' ')
else
    echo "Choose an option:"
    echo "  1) Paste pull secret directly (will be hidden)"
    echo "  2) Specify path to pull-secret file"
    echo "  3) Exit and download pull secret first"
    echo ""
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1)
            echo ""
            echo "Paste your pull secret (it will not be displayed):"
            read -s PULL_SECRET
            echo ""
            ;;
        2)
            read -p "Enter path to pull secret file: " ps_path
            if [ -f "$ps_path" ]; then
                PULL_SECRET=$(cat "$ps_path" | tr -d '\n' | tr -d ' ')
            else
                log_error "File not found: $ps_path"
                exit 1
            fi
            ;;
        3)
            echo ""
            log_warn "Please download your pull secret and save it as 'pull-secret.json'"
            log_warn "Then run this script again."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
fi

# Validate pull secret is valid JSON
if echo "$PULL_SECRET" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    log_info "Pull secret is valid JSON ✓"
else
    log_error "Pull secret is NOT valid JSON!"
    log_error "Make sure you copied the entire pull secret from Red Hat."
    exit 1
fi

# Check if it has the required registries
if echo "$PULL_SECRET" | grep -q "registry.redhat.io"; then
    log_info "Pull secret contains registry.redhat.io ✓"
else
    log_error "Pull secret missing registry.redhat.io"
    exit 1
fi

echo ""

# ============================================
# STEP 3: Update install-config.yaml
# ============================================
log_step "3/3 - Updating install-config.yaml"

# Backup existing file
if [ -f "${INSTALL_CONFIG}" ]; then
    cp "${INSTALL_CONFIG}" "${INSTALL_CONFIG}.backup.$(date +%s)"
    log_info "Backed up existing ${INSTALL_CONFIG}"
fi

# Create the install-config.yaml
cat > "${INSTALL_CONFIG}" << EOF
apiVersion: v1
metadata:
  name: aitp-lab
baseDomain: aitp-lab.local

controlPlane:
  name: master
  replicas: 3
  platform:
    baremetal: {}

compute:
  - name: worker
    replicas: 0

networking:
  networkType: OVNKubernetes
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  serviceNetwork:
    - 172.30.0.0/16
  machineNetwork:
    - cidr: 192.168.102.0/24

platform:
  baremetal:
    apiVIPs:
      - 192.168.102.10
    ingressVIPs:
      - 192.168.102.11

pullSecret: '${PULL_SECRET}'

sshKey: '${SSH_KEY}'
EOF

log_info "Created ${INSTALL_CONFIG} with your credentials"
echo ""

# ============================================
# Validation
# ============================================
log_step "Validating configuration..."

# Check file exists
if [ ! -f "${INSTALL_CONFIG}" ]; then
    log_error "${INSTALL_CONFIG} was not created!"
    exit 1
fi

# Validate YAML syntax
if python3 -c "import yaml; yaml.safe_load(open('${INSTALL_CONFIG}'))" 2>/dev/null; then
    log_info "YAML syntax is valid ✓"
else
    log_error "YAML syntax error in ${INSTALL_CONFIG}"
    exit 1
fi

# Check for placeholder values
if grep -q "YOUR_" "${INSTALL_CONFIG}"; then
    log_error "Found placeholder values still in config!"
    grep "YOUR_" "${INSTALL_CONFIG}"
    exit 1
else
    log_info "No placeholder values found ✓"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}  Configuration Complete!${NC}"
echo "=============================================="
echo ""
echo "Your ${INSTALL_CONFIG} is ready."
echo ""
echo "Next steps:"
echo "  1. Review: cat ${INSTALL_CONFIG}"
echo "  2. Copy to install dir: cp ${INSTALL_CONFIG} 01-ocp-install/"
echo "  3. Run installation: cd 01-ocp-install/scripts && ./install.sh"
echo ""

# Show summary (without exposing secrets)
echo "Configuration Summary:"
echo "  - Cluster Name: aitp-lab"
echo "  - Base Domain: aitp-lab.local"
echo "  - API VIP: 192.168.102.10"
echo "  - Ingress VIP: 192.168.102.11"
echo "  - Masters: 3"
echo "  - Workers: 0 (compact cluster)"
echo "  - SSH Key: ${SSH_KEY_FILE}"
echo "  - Pull Secret: ✓ Configured"
echo ""
