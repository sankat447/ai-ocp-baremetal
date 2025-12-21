# AI Canonical Agentic Stack - Bare Metal Installation

## Overview
This repository contains Infrastructure as Code (IaC) for deploying the AI Agentic Stack on bare-metal servers using RedHat OpenShift Container Platform 4.19.9

## Hardware Requirements
- 3x Dell VxRail E560F servers
- 32+ vCPUs, 256GB RAM, 2x 1.92TB NVMe per node
- 2x 10G NIC (bonded) per node
- Arista switches with VLAN support

## Quick Start
```bash
# Full deployment
make all

# Or step by step
make prerequisites
make install-ocp
make post-install
make gitops
make operators
make data-layer
make ai-stack
make ui-workflow
```

## Cluster Details
- **Name:** ocp419
- **Domain:** crucible.iisl.com
- **API VIP:** 192.168.102.10
- **Ingress VIP:** 192.168.102.11
- **Nodes:** 192.168.102.5-7

## Documentation
See `docs/` folder for detailed guides.
