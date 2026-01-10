# APNs Push Notification Setup Guide

## Current Status

⚠️ **APNs is currently configured with DUMMY credentials for testing**

The notification service is running but cannot send real push notifications because:
- `APNS_KEY_ID=DUMMY_KEY`
- `APNS_TEAM_ID=DUMMY_TEAM`
- Using sandbox environment (`APNS_PRODUCTION=false`)

## Required Steps to Enable Real Push Notifications

### 1. Get APNs Credentials from Apple Developer Portal

You need to obtain one of the following from [Apple Developer Portal](https://developer.apple.com/account):

#### Option A: Token-Based Authentication (Recommended)
- **APNs Auth Key (.p8 file)**: Download from Certificates, Identifiers & Profiles
- **Key ID**: 10-character string (e.g., `AB12CD34EF`)
- **Team ID**: 10-character string (e.g., `XY98ZW76VU`)

#### Option B: Certificate-Based Authentication
- **APNs Certificate (.p12 file)**: Export from Keychain Access
- **Certificate Password**: Password used when exporting

### 2. Update Kubernetes Secret

Replace the dummy credentials in the `apns-credentials` secret:

```bash
# For Token-Based Auth (.p8)
kubectl create secret generic apns-credentials \
  --from-file=apns-key.p8=/path/to/your/AuthKey_KEYID.p8 \
  --from-literal=APNS_KEY_ID=YOUR_ACTUAL_KEY_ID \
  --from-literal=APNS_TEAM_ID=YOUR_ACTUAL_TEAM_ID \
  --from-literal=APNS_BUNDLE_ID=com.app.icered.pro \
  --from-literal=APNS_PRODUCTION=false \
  --namespace=nova-staging \
  --dry-run=client -o yaml | kubectl apply -f -

# For Certificate-Based Auth (.p12)
kubectl create secret generic apns-credentials \
  --from-file=apns-cert.p12=/path/to/your/certificate.p12 \
  --from-literal=APNS_CERT_PASSWORD=your_cert_password \
  --from-literal=APNS_BUNDLE_ID=com.app.icered.pro \
  --from-literal=APNS_PRODUCTION=false \
  --namespace=nova-staging \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Restart Notification Service

After updating the secret, restart the notification service to load new credentials:

```bash
kubectl rollout restart deployment notification-service -n nova-staging
```

### 4. Verify APNs Connection

Check the logs to confirm APNs is initialized correctly:

```bash
kubectl logs -l app=notification-service -n nova-staging --tail=50 | grep -i apns
```

You should see:
```
✅ APNs push notifications enabled (production=false) from /etc/apns/apns-key.p8
```

### 5. Test Push Notifications

#### From iOS App:
1. Open the app and log in
2. Grant notification permissions when prompted
3. The app will register the device token with the backend
4. Trigger a notification event (like, comment, follow)
5. You should receive a push notification

#### Check Device Token Registration:
```bash
# View notification service logs
kubectl logs -l app=notification-service -n nova-staging --tail=100 | grep "token"
```

You should see logs like:
```
Token registered with backend successfully
```

## Production Environment

For production deployment:

1. Use production APNs credentials
2. Set `APNS_PRODUCTION=true`
3. Update the bundle ID to match your production app
4. Test thoroughly in TestFlight before releasing

## Troubleshooting

### Push Notifications Not Received

1. **Check APNs credentials are valid**
   ```bash
   kubectl get secret apns-credentials -n nova-staging -o yaml
   ```

2. **Verify device token is registered**
   - Check iOS app logs for device token
   - Check backend logs for token registration

3. **Check notification service logs**
   ```bash
   kubectl logs -l app=notification-service -n nova-staging --tail=200
   ```

4. **Verify app has notification permissions**
   - iOS Settings → Your App → Notifications → Allow Notifications

5. **Check bundle ID matches**
   - iOS app bundle ID must match `APNS_BUNDLE_ID` in secret

### Common Issues

- **"Invalid device token"**: Bundle ID mismatch or wrong environment (sandbox vs production)
- **"Certificate expired"**: Renew APNs certificate in Apple Developer Portal
- **"Connection refused"**: Check network connectivity to APNs servers
- **"Bad device token"**: Device token may be from different app or environment

## Security Notes

- Never commit APNs credentials to git
- Use Kubernetes secrets for credential storage
- Rotate credentials periodically
- Use token-based auth (.p8) for better security and no expiration
- Monitor APNs usage in Apple Developer Portal

## References

- [Apple Push Notification Service Documentation](https://developer.apple.com/documentation/usernotifications)
- [APNs Provider API](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server)
- [Token-Based Authentication](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns)
