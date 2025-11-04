Messaging Service IRSA Setup (EKS)
=================================

Goal: allow messaging-service to generate S3 presigned URLs without storing static AWS keys.

Steps
-----
1) Create IAM OIDC provider for the EKS cluster (once per cluster).
2) Create IAM role with trust policy for ServiceAccount `messaging-service` in `nova-messaging` namespace.
3) Attach minimal S3 policy (see `messaging-service-s3-presign-policy.json`).
4) Annotate the ServiceAccount with the role ARN.

Trust policy example:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/<EKS_OIDC_PROVIDER>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "<EKS_OIDC_PROVIDER>:sub": "system:serviceaccount:nova-messaging:messaging-service"
        }
      }
    }
  ]
}

Apply annotation to ServiceAccount (already templated):

metadata.annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/nova-messaging-s3-presign-role

Replace static env vars in the Deployment with IRSA (remove AWS_* keys). Keep `S3_BUCKET` and `AWS_REGION`.

