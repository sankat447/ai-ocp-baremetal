# AITP Stack Architecture

## Overview
The AITP Canonical Agentic Stack is deployed on a 3-node OpenShift compact cluster.

## Layers
1. **Cloud/Infrastructure**: Dell VxRail E560F bare-metal servers
2. **Platform**: RedHat OpenShift 4.14
3. **Storage**: OpenShift Data Foundation (Ceph)
4. **Security**: ACS, SSO, Service Mesh
5. **Data**: PostgreSQL, MongoDB, Redis, ClickHouse, Meilisearch
6. **AI**: Portkey, LangServe, LangGraph
7. **UI**: LibreChat, n8n

## Network
- Management: 192.168.101.0/24 (VLAN 101)
- Cluster: 192.168.102.0/24 (VLAN 102)
- Storage: 192.168.103.0/24 (VLAN 103)
