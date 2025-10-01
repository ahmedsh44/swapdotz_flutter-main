# Server-Authoritative DESFire Backend Deployment Guide

## Architecture Overview

This implementation provides a **server-authoritative** DESFire backend where all cryptographic operations and APDU construction happen server-side. The mobile client never handles plaintext keys or session material—it only forwards opaque APDU frames between the server and NFC card.

### Components

1. **Firebase Functions** - Session orchestration and Firestore transactions
2. **APDU Microservice** (Cloud Run) - Constructs/validates APDU frames, holds keys
3. **Mobile Client** - Pure APDU forwarder with no crypto logic

## Security Benefits

- **No client-side key exposure**: Keys never leave the backend
- **15-second TTL enforcement**: Short-lived sessions prevent replay attacks
- **Token locking**: Prevents concurrent modifications
- **Phase-based state machine**: Enforces correct operation sequence
- **Idempotency protection**: Prevents duplicate operations
- **Audit logging**: Complete transfer history

## Deployment Steps

### 1. Deploy APDU Microservice to Cloud Run

```bash
# Navigate to APDU service directory
cd apdu-svc

# Install dependencies
npm install

# Build TypeScript
npm run build

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY dist ./dist
EXPOSE 8080
CMD ["node", "dist/server.js"]
EOF

# Build and deploy to Cloud Run
gcloud builds submit --tag gcr.io/YOUR_PROJECT/apdu-svc
gcloud run deploy apdu-svc \
  --image gcr.io/YOUR_PROJECT/apdu-svc \
  --platform managed \
  --region us-central1 \
  --no-allow-unauthenticated \
  --set-env-vars "GCP_PROJECT=YOUR_PROJECT"
```

### 2. Configure Secret Manager

```bash
# Create master key secret
echo -n "YOUR_24_BYTE_HEX_KEY" | gcloud secrets create desfire-master-key \
  --data-file=- \
  --replication-policy="automatic"

# Grant access to Cloud Run service
gcloud secrets add-iam-policy-binding desfire-master-key \
  --member="serviceAccount:apdu-svc@YOUR_PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

### 3. Deploy Firebase Functions

```bash
# Navigate to functions directory
cd functions

# Install dependencies
npm install

# Set environment variables
firebase functions:config:set \
  apdu.service_url="https://apdu-svc-xxxxx.run.app" \
  functions.sa="firebase-functions@YOUR_PROJECT.iam.gserviceaccount.com"

# Deploy functions
npm run deploy
```

### 4. Configure Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Tokens collection - only functions can write
    match /tokens/{tokenId} {
      allow read: if request.auth != null;
      allow write: if false; // Only backend
    }
    
    // Sessions collection - no direct access
    match /sessions/{sessionId} {
      allow read, write: if false; // Only backend
    }
    
    // Audit ledger - read only for token owners
    match /ledger/{tokenId}/events/{eventId} {
      allow read: if request.auth != null && 
        request.auth.uid == resource.data.previousOwner ||
        request.auth.uid == resource.data.newOwner;
      allow write: if false; // Only backend
    }
  }
}
```

### 5. Update Mobile Client

Replace existing NFC handling with the forwarder pattern:

```dart
// OLD - Client handles keys
await nfcService.authenticateAndWrite(key, data);

// NEW - Server handles everything
final forwarder = DESFireForwarder();
final sessionId = await forwarder.beginAuthentication(
  tokenId: tokenId,
  userId: currentUser.uid,
);
await forwarder.changeKey(
  sessionId: sessionId,
  targetKey: 'new',
);
```

## Environment Variables

### APDU Microservice
- `GCP_PROJECT` - GCP project ID
- `PORT` - Server port (default: 8080)
- `DESFIRE_MASTER_KEY` - (Development only) Master key in hex

### Firebase Functions
- `APDU_SERVICE_URL` - Cloud Run service URL
- `FUNCTIONS_SA` - Service account email for Functions

## Monitoring & Alerts

### Key Metrics to Monitor

1. **Session TTL violations** - Sessions exceeding 15s
2. **Lock contention** - Multiple concurrent lock attempts
3. **Authentication failures** - Failed DESFire auth attempts
4. **Key change failures** - Failed ChangeKey operations

### Sample Alert Configuration

```yaml
# monitoring.yaml
alerts:
  - name: high-session-ttl-violations
    condition: |
      metric.type="cloud_function/session_ttl_violation"
      AND resource.type="cloud_function"
      AND metric.value > 5
    duration: 60s
    
  - name: authentication-failures
    condition: |
      metric.type="cloud_run/auth_failure"
      AND resource.type="cloud_run_revision"
      AND metric.value > 10
    duration: 300s
```

## Testing

### Unit Tests
```bash
# Test Firebase Functions
cd functions && npm test

# Test APDU Service
cd apdu-svc && npm test
```

### Integration Test
```bash
# Run CLI simulator
node test/cli-simulator.js
```

### End-to-End Test with Real Card
```dart
// Flutter integration test
testWidgets('Transfer flow', (tester) async {
  final forwarder = DESFireForwarder();
  
  // Mock NFC responses
  when(nfcKit.transceive(any)).thenAnswer((_) async => '9100');
  
  final sessionId = await forwarder.beginAuthentication(
    tokenId: 'test-token',
    userId: 'test-user',
  );
  
  expect(sessionId, isNotEmpty);
});
```

## Security Checklist

- [ ] APDU service has no public ingress
- [ ] IAM/OIDC authentication enforced
- [ ] Master key in Secret Manager (not env vars)
- [ ] VPC egress only for Cloud Run
- [ ] Request/response logging disabled in production
- [ ] SSL/TLS for all communications
- [ ] Firestore security rules deployed
- [ ] Session TTL set to 15 seconds
- [ ] Idempotency keys implemented
- [ ] Audit logging enabled

## Rollback Procedure

1. **Immediate rollback**: Redeploy previous Cloud Run/Functions versions
2. **Key compromise**: Rotate master key in Secret Manager
3. **Data recovery**: Use audit logs to reconstruct state

## Phase 2 Enhancements

- Implement full Secure Messaging (CRC32, padding, CBC encryption, CMAC)
- Add AES authentication support (0xAA opcode)
- Implement read/write operations under SM
- Add multi-application support
- Implement key diversification per token

## Support

For issues or questions:
- Check audit logs in `/ledger/{tokenId}/events`
- Review Cloud Run logs for APDU service errors
- Check Firebase Functions logs for session errors
- Verify Firestore lock states in `/tokens/{tokenId}` 