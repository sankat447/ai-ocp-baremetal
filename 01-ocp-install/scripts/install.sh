#!/bin/bash
set -euo pipefail

OCP_VERSION="4.14.12"
INSTALL_DIR="./cluster-install"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
echo "AITP Lab - OCP ${OCP_VERSION} Installation"
echo "=========================================="

detect_architecture() {
    log_info "Detecting system architecture..."
    ARCH=$(uname -m)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    echo "  Detected: ${OS} ${ARCH}"
    
    case "${ARCH}" in
        x86_64|amd64) ARCH_SUFFIX="linux" ;;
        aarch64|arm64) ARCH_SUFFIX="linux-arm64" ;;
        *) log_error "Unsupported architecture: ${ARCH}"; exit 1 ;;
    esac
}

download_tools() {
    log_info "[1/7] Downloading OpenShift tools..."
    
    MIRROR="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}"
    
    rm -f openshift-install oc kubectl openshift-*.tar.gz
    
    if [ "${ARCH}" == "x86_64" ] || [ "${ARCH}" == "amd64" ]; then
        INSTALLER_TAR="openshift-install-linux.tar.gz"
        CLIENT_TAR="openshift-client-linux.tar.gz"
    else
        INSTALLER_TAR="openshift-install-linux-arm64.tar.gz"
        CLIENT_TAR="openshift-client-linux-arm64.tar.gz"
    fi
    
    curl -LO "${MIRROR}/${INSTALLER_TAR}"
    tar xzf "${INSTALLER_TAR}" openshift-install
    rm -f "${INSTALLER_TAR}"
    
    curl -LO "${MIRROR}/${CLIENT_TAR}"
    tar xzf "${CLIENT_TAR}" oc kubectl
    rm -f "${CLIENT_TAR}"
    
    chmod +x openshift-install oc kubectl
    
    log_info "Validating binaries..."
    ./openshift-install version
}

prepare_install_dir() {
    log_info "[2/7] Preparing installation directory..."
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    cp ../install-config.yaml "${INSTALL_DIR}/"
    cp ../agent-config.yaml "${INSTALL_DIR}/"
}

generate_iso() {
    log_info "[3/7] Generating agent boot ISO..."
    ./openshift-install agent create image --dir="${INSTALL_DIR}" --log-level=info
    
    if [ -f "${INSTALL_DIR}/agent.x86_64.iso" ]; then
        log_info "ISO generated: ${INSTALL_DIR}/agent.x86_64.iso"
    elif [ -f "${INSTALL_DIR}/agent.aarch64.iso" ]; then
        log_info "ISO generated: ${INSTALL_DIR}/agent.aarch64.iso"
    else
        log_error "ISO generation failed!"
        exit 1
    fi
}

upload_iso() {
    log_info "[4/7] Uploading ISO to iDRAC..."
    
    IDRAC_IPS=("192.168.101.5" "192.168.101.6" "192.168.101.7")
    IDRAC_USER="${IDRAC_USER:-root}"
    IDRAC_PASS="${IDRAC_PASSWORD:-calvin}"
    
    ISO_FILE=$(find "${INSTALL_DIR}" -name "agent.*.iso" | head -1)
    HTTP_SERVER_IP=$(hostname -I | awk '{print $1}')
    
    pkill -f "python.*8080" || true
    cd "${INSTALL_DIR}"
    python3 -m http.server 8080 &
    HTTP_PID=$!
    cd - > /dev/null
    
    ISO_FILENAME=$(basename "${ISO_FILE}")
    ISO_URL="http://${HTTP_SERVER_IP}:8080/${ISO_FILENAME}"
    
    log_info "ISO URL: ${ISO_URL}"
    
    for IDRAC_IP in "${IDRAC_IPS[@]}"; do
        log_info "Mounting ISO on ${IDRAC_IP}..."
        
        curl -sk -u "${IDRAC_USER}:${IDRAC_PASS}" -X POST \
            "https://${IDRAC_IP}/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.EjectMedia" 2>/dev/null || true
        
        sleep 2
        
        curl -sk -u "${IDRAC_USER}:${IDRAC_PASS}" -X POST \
            -H "Content-Type: application/json" \
            -d "{\"Image\": \"${ISO_URL}\", \"Inserted\": true}" \
            "https://${IDRAC_IP}/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia"
        
        curl -sk -u "${IDRAC_USER}:${IDRAC_PASS}" -X PATCH \
            -H "Content-Type: application/json" \
            -d '{"Boot": {"BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd"}}' \
            "https://${IDRAC_IP}/redfish/v1/Systems/System.Embedded.1"
    done
}

boot_nodes() {
    log_info "[5/7] Rebooting nodes..."
    
    IDRAC_IPS=("192.168.101.5" "192.168.101.6" "192.168.101.7")
    IDRAC_USER="${IDRAC_USER:-root}"
    IDRAC_PASS="${IDRAC_PASSWORD:-calvin}"
    
    for IDRAC_IP in "${IDRAC_IPS[@]}"; do
        curl -sk -u "${IDRAC_USER}:${IDRAC_PASS}" -X POST \
            -H "Content-Type: application/json" \
            -d '{"ResetType": "ForceRestart"}' \
            "https://${IDRAC_IP}/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset"
        log_info "Reboot sent to ${IDRAC_IP}"
    done
}

wait_for_install() {
    log_info "[6/7] Waiting for installation..."
    ./openshift-install agent wait-for bootstrap-complete --dir="${INSTALL_DIR}" --log-level=info
    ./openshift-install agent wait-for install-complete --dir="${INSTALL_DIR}" --log-level=info
}

verify_install() {
    log_info "[7/7] Verifying installation..."
    export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"
    ./oc get nodes
    ./oc get co
    echo ""
    echo "Console: $(./oc whoami --show-console)"
    echo "Password: $(cat ${INSTALL_DIR}/auth/kubeadmin-password)"
}

main() {
    detect_architecture
    download_tools
    prepare_install_dir
    generate_iso
    upload_iso
    boot_nodes
    wait_for_install
    verify_install
    echo "Installation Complete!"
}

main "$@"
