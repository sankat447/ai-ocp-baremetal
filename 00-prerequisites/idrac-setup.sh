#!/bin/bash
# Configure Dell iDRAC for PXE/Virtual Media boot

set -euo pipefail

IDRAC_IPS=("192.168.101.5" "192.168.101.6" "192.168.101.7")
IDRAC_USER="${IDRAC_USER:-root}"
IDRAC_PASS="${IDRAC_PASSWORD:-il02iis!}"

echo "=== Dell iDRAC Configuration Script ==="

for IDRAC_IP in "${IDRAC_IPS[@]}"; do
  echo ""
  echo "Configuring iDRAC: $IDRAC_IP"
  echo "================================"
  
  # Enable virtualization in BIOS
  echo "  Setting BIOS virtualization options..."
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    set BIOS.ProcSettings.LogicalProc Enabled 2>/dev/null || true
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    set BIOS.ProcSettings.Virtualization Enabled 2>/dev/null || true
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    set BIOS.ProcSettings.VtForDirectIo Enabled 2>/dev/null || true
  
  # Set boot order
  echo "  Setting boot order..."
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    set BIOS.BiosBootSettings.BootSeq VCD,HDD 2>/dev/null || true
  
  # Enable Virtual Media
  echo "  Enabling Virtual Media..."
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    set iDRAC.VirtualMedia.Attached 1 2>/dev/null || true
  
  # Create config job
  echo "  Creating BIOS config job..."
  racadm -r $IDRAC_IP -u $IDRAC_USER -p $IDRAC_PASS \
    jobqueue create BIOS.Setup.1-1 2>/dev/null || true
    
  echo "  ✓ Configuration sent to $IDRAC_IP"
done

echo ""
echo "=== Configuration Complete ==="
echo "Reboot servers to apply BIOS changes"
