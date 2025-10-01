# App Version Control System

## Overview

SwapDotz enforces mandatory app updates to ensure all users are running the latest, most secure version of the app. This prevents old, potentially vulnerable versions from accessing the NFC token system.

## How It Works

### 1. Version Check on Startup
- App checks current version against Firebase config on launch
- If outdated, blocks access and shows update screen
- Cannot bypass - the app is completely locked

### 2. Version Check on NFC Operations
- Double-checks version before each NFC scan
- Prevents any workaround attempts
- Immediately redirects to update screen if outdated

### 3. Server Configuration
The minimum required version is stored in Firestore:
```
/config/app_requirements
{
  "minimum_version": "1.2.0",
  "update_message": "Critical security update required",
  "update_url": "https://custom-update-url.com", // Optional
  "force_update_after": "2024-12-31T23:59:59Z", // Optional deadline
}
```

## Setting Up Version Control

### 1. Initial Firebase Setup
Create the config document in Firestore:
```javascript
// In Firebase Console or using Admin SDK
await firestore.collection('config').doc('app_requirements').set({
  minimum_version: '1.0.0',
  update_message: 'Please update to the latest version.',
  updated_at: FieldValue.serverTimestamp()
});
```

### 2. Update Version Requirements
Use the Cloud Function to update requirements:
```dart
await firebaseService.functions.httpsCallable('updateVersionRequirements').call({
  'minimum_version': '1.2.0',
  'update_message': 'Security patch - update required immediately',
  'update_url': 'https://apps.apple.com/app/swapdotz/id123456',
  'reason': 'CVE-2024-001 security patch'
});
```

### 3. Configure App Store URLs
In `version_check_screen.dart`, update the store URLs:
```dart
// iOS App Store
url = 'https://apps.apple.com/app/swapdotz/id[YOUR_APP_ID]';

// Google Play Store  
url = 'https://play.google.com/store/apps/details?id=[YOUR_PACKAGE_ID]';
```

## Version Format

Versions must follow semantic versioning: `MAJOR.MINOR.PATCH`

Examples:
- `1.0.0` - Initial release
- `1.0.1` - Bug fix
- `1.1.0` - New features
- `2.0.0` - Breaking changes

## Version Comparison Logic

The app compares versions numerically:
```dart
1.0.9 < 1.0.10  // Correct numerical comparison
1.2.0 > 1.1.99  // Major/minor takes precedence
2.0.0 > 1.99.99 // Major version wins
```

## Update Scenarios

### Scenario 1: Regular Update
```json
{
  "minimum_version": "1.1.0",
  "update_message": "New features available! Update to access them."
}
```
Users see a friendly update prompt.

### Scenario 2: Security Update
```json
{
  "minimum_version": "1.1.1",
  "update_message": "Critical security patch. Update required for continued access.",
  "update_url": "https://swapdotz.com/security-update-info"
}
```
Urgent messaging with additional info link.

### Scenario 3: Emergency Update
```json
{
  "minimum_version": "2.0.0",
  "update_message": "URGENT: Security vulnerability detected. Update immediately.",
  "force_update_after": "2024-01-15T00:00:00Z"
}
```
Shows deadline and blocks all access after date.

## Admin Functions

### Check Version Status
```typescript
// Cloud Function to check if a version is allowed
const result = await checkVersionAllowed({ version: '1.0.5' });
// Returns: { allowed: false, minimum_version: '1.1.0', ... }
```

### Batch User Notifications
When updating version requirements, consider:
1. Push notifications to warn users
2. Grace period for non-critical updates
3. Clear communication about why update is needed

## Security Benefits

1. **Vulnerability Patching**: Force updates when security issues are found
2. **Protocol Updates**: Ensure all clients support latest NFC protocols
3. **Feature Consistency**: All users have same capabilities
4. **Compliance**: Meet regulatory requirements for security updates

## Testing Version Control

### 1. Test Outdated Version
```dart
// Temporarily set a future version requirement
await updateVersionRequirements({
  minimum_version: '99.0.0',
  update_message: 'Test message'
});
```

### 2. Test Update Flow
1. Launch app with outdated version
2. Verify update screen appears
3. Check store link works correctly
4. Verify cannot access NFC features

### 3. Reset After Testing
```dart
await updateVersionRequirements({
  minimum_version: '1.0.0'
});
```

## Best Practices

1. **Gradual Rollouts**: Give users time to update for non-critical changes
2. **Clear Messaging**: Explain why the update is necessary
3. **Test Thoroughly**: Ensure update links work on all platforms
4. **Monitor Adoption**: Track how many users are on latest version
5. **Emergency Protocol**: Have a plan for critical security updates

## Common Issues

### App Store Delays
- iOS App Store review can take 24-48 hours
- Plan version requirements accordingly
- Consider phased rollouts

### User Resistance
- Provide clear benefits of updating
- Make updates as small as possible
- Ensure update process is smooth

### Version Check Failures
- App continues if Firebase is unreachable
- Consider caching last known requirement
- Log failures for monitoring

## Integration with CI/CD

Automate version updates in your deployment pipeline:
```yaml
# Example GitHub Action
- name: Update Firebase Version Requirement
  run: |
    VERSION=$(cat pubspec.yaml | grep version: | head -1 | awk '{print $2}')
    firebase functions:call updateVersionRequirements --data '{"minimum_version":"'$VERSION'"}'
```

## Monitoring

Track version adoption in Firebase Analytics:
```dart
// Log app version on startup
await FirebaseAnalytics.instance.setUserProperty(
  name: 'app_version',
  value: packageInfo.version,
);
```

## Future Enhancements

1. **A/B Testing**: Different version requirements for user segments
2. **Staged Rollouts**: Gradually increase minimum version
3. **Feature Flags**: Enable features based on version
4. **Offline Caching**: Remember version requirements offline
5. **Custom Update UI**: Platform-specific update experiences 