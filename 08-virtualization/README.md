# OpenShift Virtualization & MTV IaC Module

## Overview

This module provides Infrastructure as Code (IaC) for:
- **OpenShift Virtualization (CNV)** - Run and manage virtual machines alongside containers
- **MTV (Migration Toolkit for Virtualization)** - Migrate VMs from VMware, RHV, or other platforms

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────┐    ┌──────────────────────┐          │
│  │ OpenShift            │    │ Migration Toolkit    │          │
│  │ Virtualization (CNV) │    │ for Virtualization   │          │
│  │                      │    │ (MTV/Forklift)       │          │
│  │ - KubeVirt           │    │                      │          │
│  │ - CDI (Data Import)  │    │ - Provider Mgmt      │          │
│  │ - Hostpath Provisioner│   │ - Migration Plans    │          │
│  │ - Network Addons     │    │ - Warm Migration     │          │
│  └──────────────────────┘    └──────────────────────┘          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Virtual Machines                        │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐     │  │
│  │  │ RHEL 9  │  │ CentOS  │  │ Fedora  │  │ Windows │     │  │
│  │  │ VM      │  │ VM      │  │ VM      │  │ VM      │     │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Storage: ODF (Ceph RBD)    Network: OVN-Kubernetes       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
08-virtualization/
├── operators/
│   ├── cnv-namespace.yaml          # CNV namespace
│   ├── cnv-operatorgroup.yaml      # CNV operator group
│   ├── cnv-subscription.yaml       # CNV operator subscription
│   └── cnv-hyperconverged.yaml     # HyperConverged CR (enables CNV)
├── mtv/
│   ├── mtv-namespace.yaml          # MTV namespace
│   ├── mtv-operatorgroup.yaml      # MTV operator group
│   ├── mtv-subscription.yaml       # MTV operator subscription
│   ├── mtv-forkliftcontroller.yaml # Forklift controller CR
│   └── mtv-migration-examples.yaml # Provider & migration examples
├── templates/
│   ├── vm-namespace.yaml           # Namespace for VMs
│   ├── datavolumes-os-images.yaml  # OS image DataVolumes
│   └── vm-templates.yaml           # VM templates (S/M/L)
├── vm-examples/
│   └── example-vms.yaml            # Ready-to-deploy example VMs
├── ansible/
│   ├── inventory                   # Ansible inventory
│   └── provision-vm.yaml           # VM provisioning playbook
├── kustomization.yaml              # Kustomize configuration
└── README.md                       # This file
```

## Prerequisites

1. **OpenShift 4.14+** with ODF storage
2. **Hardware virtualization** enabled on nodes (Intel VT-x or AMD-V)
3. **Storage class** with ReadWriteMany support (e.g., `ocs-storagecluster-ceph-rbd`)
4. **Cluster admin** privileges

### Verify Hardware Virtualization

```bash
# Check if virtualization is enabled on nodes
oc debug node/<node-name> -- chroot /host cat /proc/cpuinfo | grep -E 'vmx|svm'
```

## Installation

### Step 1: Install CNV Operator

```bash
# Apply CNV operator resources
oc apply -f operators/cnv-namespace.yaml
oc apply -f operators/cnv-operatorgroup.yaml
oc apply -f operators/cnv-subscription.yaml

# Wait for operator to be ready
oc wait --for=condition=Ready pod -l name=kubevirt-hyperconverged-operator -n openshift-cnv --timeout=5m
```

### Step 2: Deploy HyperConverged CR

```bash
# Deploy CNV components
oc apply -f operators/cnv-hyperconverged.yaml

# Wait for CNV to be fully deployed (may take 10-15 minutes)
oc wait --for=condition=Available hco kubevirt-hyperconverged -n openshift-cnv --timeout=15m
```

### Step 3: Install MTV Operator

```bash
# Apply MTV operator resources
oc apply -f mtv/mtv-namespace.yaml
oc apply -f mtv/mtv-operatorgroup.yaml
oc apply -f mtv/mtv-subscription.yaml

# Wait for MTV operator
oc wait --for=condition=Ready pod -l app=forklift-operator -n openshift-mtv --timeout=5m
```

### Step 4: Deploy ForkliftController

```bash
# Deploy MTV components
oc apply -f mtv/mtv-forkliftcontroller.yaml

# Wait for Forklift to be ready
oc wait --for=condition=Successful forkliftcontroller forklift-controller -n openshift-mtv --timeout=10m
```

### Step 5: Import OS Images (Optional)

```bash
# Create namespace for OS images
oc apply -f templates/vm-namespace.yaml

# Import base OS images
oc apply -f templates/datavolumes-os-images.yaml

# Check import progress
oc get datavolumes -n openshift-virtualization-os-images -w
```

## Using Makefile

The main Makefile includes targets for virtualization:

```bash
# Install everything
make virtualization

# Or step by step
make cnv-operator      # Install CNV operator
make cnv-deploy        # Deploy HyperConverged
make mtv-operator      # Install MTV operator
make mtv-deploy        # Deploy ForkliftController
make vm-templates      # Deploy VM templates
```

## Provisioning VMs

### Using kubectl/oc

```bash
# Create a VM from template
oc apply -f vm-examples/example-vms.yaml

# Start a VM
oc patch vm dev-server-01 -n aitp-vms --type merge -p '{"spec":{"running":true}}'

# Stop a VM
oc patch vm dev-server-01 -n aitp-vms --type merge -p '{"spec":{"running":false}}'

# Access VM console
virtctl console dev-server-01 -n aitp-vms

# SSH into VM (via NodePort or Route)
virtctl ssh cloud-user@dev-server-01 -n aitp-vms
```

### Using Ansible

```bash
# Provision a single VM
ansible-playbook -i ansible/inventory ansible/provision-vm.yaml \
  -e "vm_name=my-new-vm" \
  -e "vm_size=medium" \
  -e "vm_namespace=aitp-vms"

# Provision with SSH key
ansible-playbook -i ansible/inventory ansible/provision-vm.yaml \
  -e "vm_name=secure-vm" \
  -e "vm_size=large" \
  -e "vm_ssh_key='ssh-rsa AAAA...'"
```

## VM Migration with MTV

### 1. Configure Source Provider

Edit `mtv/mtv-migration-examples.yaml` with your vSphere or RHV details:

```yaml
# For vSphere
spec:
  type: vsphere
  url: "https://your-vcenter.com/sdk"
```

### 2. Create Provider and Credentials

```bash
# Edit credentials first!
vi mtv/mtv-migration-examples.yaml

# Apply provider configuration
oc apply -f mtv/mtv-migration-examples.yaml
```

### 3. Create Migration Plan via UI

1. Access MTV UI: `https://virt.apps.<cluster-domain>/`
2. Add Provider → Enter vSphere/RHV credentials
3. Create Storage & Network Mappings
4. Create Migration Plan → Select VMs
5. Execute Migration

### 4. Monitor Migration

```bash
# Check migration status
oc get migration -n openshift-mtv

# View detailed migration logs
oc logs -l app=forklift-controller -n openshift-mtv -f
```

## VM Sizes Reference

| Size   | vCPU | Memory | Root Disk |
|--------|------|--------|-----------|
| Small  | 2    | 4 GB   | 30 GB     |
| Medium | 4    | 8 GB   | 50 GB     |
| Large  | 8    | 16 GB  | 100 GB    |
| XLarge | 16   | 32 GB  | 200 GB    |

## Networking Options

### Default (Masquerade)
- VMs get pod network IPs
- Best for most workloads

### Bridge Network
- Direct L2 access
- Required for some legacy apps

### SR-IOV
- Near-native network performance
- Requires SR-IOV capable NICs

## Troubleshooting

### VM Won't Start

```bash
# Check VMI status
oc describe vmi <vm-name> -n <namespace>

# Check virt-launcher pod
oc logs virt-launcher-<vm-name>-xxxxx -n <namespace>

# Common issues:
# - Insufficient resources
# - Storage not available
# - Image import failed
```

### DataVolume Stuck

```bash
# Check CDI import pods
oc get pods -n openshift-cnv | grep importer

# View importer logs
oc logs <importer-pod> -n openshift-cnv
```

### MTV Migration Failed

```bash
# Check migration status
oc describe migration <migration-name> -n openshift-mtv

# View conversion pod logs
oc logs <virt-v2v-pod> -n openshift-mtv
```

## Security Considerations

1. **VM Password** - Change default passwords immediately
2. **SSH Keys** - Use SSH keys instead of passwords
3. **Network Policies** - Apply network policies to VM namespaces
4. **RBAC** - Restrict VM management to authorized users
5. **Encryption** - Enable storage encryption for sensitive VMs

## References

- [OpenShift Virtualization Documentation](https://docs.openshift.com/container-platform/latest/virt/about_virt/about-virt.html)
- [MTV Documentation](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CDI Documentation](https://github.com/kubevirt/containerized-data-importer)
