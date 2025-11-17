# EKS Cluster Upgrade Plan

## Current Status
- **Current Version**: 1.29
- **Target Version**: 1.31
- **kubectl Client**: 1.34.1
- **Cluster**: nova-staging (ap-northeast-1)

## Upgrade Strategy

⚠️ **IMPORTANT**: EKS only supports upgrading one minor version at a time.

### Upgrade Path: 1.29 → 1.30 → 1.31

## Step-by-Step Execution

### Phase 1: Upgrade to 1.30

1. **Update Terraform configuration**
   ```bash
   # Edit terraform/eks.tf, change version to "1.30"
   cd terraform
   ```

2. **Plan the upgrade**
   ```bash
   terraform plan -var-file=staging.tfvars -out=upgrade-1.30.plan
   ```

3. **Review the plan carefully**
   - Verify only the cluster version changes
   - Check for any other unexpected changes

4. **Apply the upgrade**
   ```bash
   terraform apply upgrade-1.30.plan
   ```
   ⏱️ Expected time: 20-30 minutes

5. **Wait for cluster to be ACTIVE**
   ```bash
   aws eks describe-cluster --name nova-staging --region ap-northeast-1 --query 'cluster.status'
   ```

6. **Update kubeconfig**
   ```bash
   aws eks update-kubeconfig --region ap-northeast-1 --name nova-staging
   ```

7. **Verify cluster health**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   kubectl version
   ```

### Phase 2: Upgrade Node Groups

⚠️ After control plane upgrade, nodes will continue to run on old version until node group is upgraded.

1. **Check current node version**
   ```bash
   kubectl get nodes -o wide
   ```

2. **Upgrade managed node groups**

   Terraform will automatically trigger node group updates. Nodes will be:
   - Cordoned (no new pods scheduled)
   - Drained (existing pods moved)
   - Terminated and replaced with new version

   This happens automatically with rolling update strategy.

3. **Monitor node group upgrade**
   ```bash
   watch kubectl get nodes
   ```

### Phase 3: Upgrade to 1.31

1. **Update Terraform configuration**
   ```bash
   # Already done - terraform/eks.tf shows version "1.31"
   ```

2. **Plan the upgrade**
   ```bash
   cd terraform
   terraform plan -var-file=staging.tfvars -out=upgrade-1.31.plan
   ```

3. **Apply the upgrade**
   ```bash
   terraform apply upgrade-1.31.plan
   ```

4. **Wait and verify** (same steps as Phase 1, steps 5-7)

### Phase 4: Update Add-ons (if needed)

Check and update EKS add-ons compatibility:

```bash
# List current add-ons
aws eks list-addons --cluster-name nova-staging --region ap-northeast-1

# Check recommended versions for 1.31
aws eks describe-addon-versions --kubernetes-version 1.31 --region ap-northeast-1 \
  --addon-name vpc-cni --query 'addons[0].addonVersions[0].addonVersion'

# Common add-ons to check:
# - vpc-cni
# - coredns
# - kube-proxy
# - aws-ebs-csi-driver
```

## Pre-upgrade Checklist

- [ ] Backup important data and configurations
- [ ] Review [EKS version compatibility](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [ ] Check application compatibility with target Kubernetes version
- [ ] Ensure maintenance window is scheduled
- [ ] Notify team members
- [ ] Have rollback plan ready

## Rollback Plan

If issues occur during upgrade:

1. **Control plane rollback** - NOT supported by AWS (upgrade is one-way)
2. **Mitigation strategies**:
   - Node groups can run older versions temporarily
   - Restore from backups if needed
   - Scale up old version nodes, drain new ones

## Post-Upgrade Verification

```bash
# 1. Cluster version
aws eks describe-cluster --name nova-staging --region ap-northeast-1 \
  --query 'cluster.{Version:version,Status:status}'

# 2. Node versions
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion

# 3. Pods health
kubectl get pods -A | grep -v Running

# 4. Cluster endpoints
kubectl cluster-info

# 5. Version alignment check
kubectl version
# Client and server should be within ±1 minor version
```

## Timeline Estimate

- **Phase 1** (1.29→1.30): ~30 minutes (control plane) + ~15 minutes (nodes)
- **Phase 2** (1.30→1.31): ~30 minutes (control plane) + ~15 minutes (nodes)
- **Total**: ~90 minutes with buffer time

## References

- [Amazon EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Updating an Amazon EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
