# Troubleshooting Guide

## Common Issues

### OCP Installation Fails
1. Check DNS resolution: `nslookup api.aitp-lab.local`
2. Verify iDRAC connectivity: `ping 192.168.101.5`
3. Check ISO is mounted via iDRAC console

### Pods Not Starting
1. Check storage: `oc get pvc -A`
2. Check operator status: `oc get csv -A`
3. View pod logs: `oc logs -f <pod> -n <namespace>`

### Network Issues
1. Verify service mesh: `oc get smcp -n istio-system`
2. Check network policies: `oc get networkpolicy -A`
