# Alice Voice Service - GCP Secrets Configuration

## Overview

This guide explains how to configure the required API keys for Alice Voice Service in GCP Secret Manager.

## Required Secrets

| Secret Name | Description | Where to Get |
|-------------|-------------|--------------|
| `nova-alice-voice-agora-app-id` | Agora RTC App ID | [Agora Console](https://console.agora.io) |
| `nova-alice-voice-agora-certificate` | Agora App Certificate | [Agora Console](https://console.agora.io) |
| `nova-alice-voice-deepgram-api-key` | Deepgram STT API Key | [Deepgram Console](https://console.deepgram.com) |
| `nova-alice-voice-openai-api-key` | OpenAI API Key | [OpenAI Platform](https://platform.openai.com/api-keys) |

## Setup Steps

### 1. Create Secrets in GCP Secret Manager

```bash
# Set your project
export PROJECT_ID="nova-social-staging"

# Create Agora App ID secret
echo -n "YOUR_AGORA_APP_ID" | gcloud secrets create nova-alice-voice-agora-app-id \
    --project=$PROJECT_ID \
    --data-file=-

# Create Agora Certificate secret
echo -n "YOUR_AGORA_CERTIFICATE" | gcloud secrets create nova-alice-voice-agora-certificate \
    --project=$PROJECT_ID \
    --data-file=-

# Create Deepgram API Key secret
echo -n "YOUR_DEEPGRAM_KEY" | gcloud secrets create nova-alice-voice-deepgram-api-key \
    --project=$PROJECT_ID \
    --data-file=-

# Create OpenAI API Key secret
echo -n "YOUR_OPENAI_KEY" | gcloud secrets create nova-alice-voice-openai-api-key \
    --project=$PROJECT_ID \
    --data-file=-
```

### 2. Grant GKE Service Account Access

```bash
# Get the GKE service account
export GKE_SA="nova-gke-nodes@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant secret accessor role for each secret
for SECRET in nova-alice-voice-agora-app-id nova-alice-voice-agora-certificate nova-alice-voice-deepgram-api-key nova-alice-voice-openai-api-key; do
    gcloud secrets add-iam-policy-binding $SECRET \
        --project=$PROJECT_ID \
        --member="serviceAccount:${GKE_SA}" \
        --role="roles/secretmanager.secretAccessor"
done
```

### 3. Install External Secrets Operator (if not already installed)

```bash
# Add the External Secrets Helm repo
helm repo add external-secrets https://charts.external-secrets.io

# Install External Secrets Operator
helm install external-secrets \
    external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --set installCRDs=true
```

### 4. Create SecretStore for GCP

```yaml
# k8s/base/gcp-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: gcp-secret-manager
  namespace: nova-staging
spec:
  provider:
    gcpsm:
      projectID: nova-social-staging
```

### 5. Create ExternalSecret for Alice Voice Service

The ExternalSecret is already defined in `k8s/microservices/alice-voice-service-secret.yaml` (commented section). Uncomment and apply:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: alice-voice-service-external-secret
  namespace: nova-staging
spec:
  secretStoreRef:
    name: gcp-secret-manager
    kind: SecretStore
  target:
    name: alice-voice-service-secret
  data:
  - secretKey: agora-app-id
    remoteRef:
      key: nova-alice-voice-agora-app-id
  - secretKey: agora-app-certificate
    remoteRef:
      key: nova-alice-voice-agora-certificate
  - secretKey: deepgram-api-key
    remoteRef:
      key: nova-alice-voice-deepgram-api-key
  - secretKey: openai-api-key
    remoteRef:
      key: nova-alice-voice-openai-api-key
```

## Manual Secret Update (Without External Secrets)

If not using External Secrets Operator, update the Kubernetes secret directly:

```bash
# Create the secret from literal values
kubectl create secret generic alice-voice-service-secret \
    -n nova-staging \
    --from-literal=agora-app-id=YOUR_AGORA_APP_ID \
    --from-literal=agora-app-certificate=YOUR_CERTIFICATE \
    --from-literal=deepgram-api-key=YOUR_DEEPGRAM_KEY \
    --from-literal=openai-api-key=YOUR_OPENAI_KEY \
    --dry-run=client -o yaml | kubectl apply -f -
```

## Verify Secrets

```bash
# Check secret exists
kubectl get secret alice-voice-service-secret -n nova-staging

# Verify secret keys (not values)
kubectl get secret alice-voice-service-secret -n nova-staging -o jsonpath='{.data}' | jq 'keys'
```

## Current API Keys Reference

The following API keys are already configured in the Nova project:

- **Agora App ID**: `d371c9215217473abe07541327cbf3d4`
- **Deepgram**: Already in use for STT
- **OpenAI**: Using tu-zi.com proxy at `https://api.tu-zi.com/v1`

## Troubleshooting

### Secret Not Found

```bash
# Check if ExternalSecret synced
kubectl get externalsecret alice-voice-service-external-secret -n nova-staging

# Check SecretStore status
kubectl get secretstore gcp-secret-manager -n nova-staging
```

### Permission Denied

```bash
# Verify IAM binding
gcloud secrets get-iam-policy nova-alice-voice-agora-app-id --project=$PROJECT_ID
```
