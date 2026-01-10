# GCP GitHub Actions Setup

These workflows deploy to GKE using `gcloud` + Workload Identity Federation:

- `.github/workflows/staging-gcp-kubectl-apply.yml`
- `.github/workflows/production-gcp-kubectl-apply.yml` (manual)

## Required Repository Variables

Set these in **GitHub → Settings → Secrets and variables → Actions → Variables**:

- `GCP_PROJECT_ID` (e.g. `banded-pad-479802-k9`)
- `GCP_WORKLOAD_IDENTITY_PROVIDER` (full resource name, e.g. `projects/…/locations/global/workloadIdentityPools/…/providers/…`)
- `GCP_SERVICE_ACCOUNT` (service account email, e.g. `github-actions@PROJECT.iam.gserviceaccount.com`)

Optional (defaults exist in workflows):

- `GCP_REGION` (default `asia-northeast1`)
- `GKE_CLUSTER` (default staging cluster `nova-staging-gke`)

## Notes

- Staging apply renders and applies both `k8s/infrastructure/overlays/staging` and `backend/k8s/overlays/staging`.
- Production apply is `workflow_dispatch` only and expects `k8s/overlays/production` + `backend/k8s/overlays/prod` to match your production cluster.
