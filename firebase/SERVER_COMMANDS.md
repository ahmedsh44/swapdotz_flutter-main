# Server Command Execution System

## Overview

The SwapDotz platform supports remote administration of NFC tokens through server-initiated commands. This allows critical security updates, encryption upgrades, and emergency responses without requiring physical access to tokens.

## Architecture

```
Firebase Console/Admin → Cloud Function → Firestore → Mobile App → NFC Token
```

1. **Admin triggers command** via Firebase Console or admin API
2. **Cloud Function validates** and queues command in Firestore
3. **Mobile app checks** for pending commands when scanning
4. **App executes command** on the NFC token
5. **Results logged** back to Firestore

## Supported Commands

### 1. `upgrade_des_to_aes`
Upgrades legacy DES authentication to modern AES-128 encryption.

```json
{
  "type": "upgrade_des_to_aes",
  "priority": "high",
  "params": {
    "new_aes_key": "a1b2c3d4e5f67890123456789012345",
    "backup_data": true
  }
}
```

### 2. `rotate_master_key`
Changes the card's master authentication key for security.

```json
{
  "type": "rotate_master_key",
  "priority": "critical",
  "params": {
    "new_key": "fedcba9876543210fedcba9876543210"
  }
}
```

### 3. `change_file_permissions`
Modifies access rights for specific files on the token.

```json
{
  "type": "change_file_permissions",
  "priority": "normal",
  "params": {
    "file_id": 1,
    "permissions": {
      "read": "free",
      "write": "key0",
      "readWrite": "key0",
      "changeAccess": "never"
    }
  }
}
```

### 4. `add_new_application`
Installs a new application on the DESFire card.

```json
{
  "type": "add_new_application",
  "priority": "normal",
  "params": {
    "app_id": 2,
    "key_settings": {
      "numberOfKeys": 3,
      "maxKeySize": 16
    }
  }
}
```

### 5. `emergency_lockdown`
Immediately locks a compromised or lost token.

```json
{
  "type": "emergency_lockdown",
  "priority": "critical",
  "params": {
    "reason": "reported_stolen"
  }
}
```

### 6. `firmware_update`
Queues firmware updates for compatible tokens.

```json
{
  "type": "firmware_update",
  "priority": "low",
  "params": {
    "version": "2.1.0",
    "features": ["enhanced_crypto", "nfc_type_5"]
  }
}
```

### 7. `diagnostic_scan`
Collects detailed token information for troubleshooting.

```json
{
  "type": "diagnostic_scan",
  "priority": "normal",
  "params": {
    "include_memory_map": true,
    "test_crypto": true
  }
}
```

## Command Flow

### 1. Queueing a Command (Server Side)

```dart
// Admin queues encryption upgrade
await firebaseService.queueServerCommand('TOKEN_UID_123', {
  'type': 'upgrade_des_to_aes',
  'priority': 'high',
  'params': {
    'backup_data': true
  }
});
```

### 2. Command Detection (Client Side)

When a user scans their token:

```dart
// Check for pending commands
final tokenDoc = await FirebaseFirestore.instance
    .collection('tokens')
    .doc(tag.id)
    .get();

final serverCommand = tokenDoc.data()?['pending_command'];
if (serverCommand != null) {
  await _executeServerCommand(desfire, serverCommand, tag.id);
}
```

### 3. Command Execution

The app executes the command and handles errors gracefully:

```dart
switch (commandType) {
  case 'upgrade_des_to_aes':
    // Authenticate with old DES key
    await desfire.authenticateLegacy();
    // Change to AES
    await desfire.changeKey(0x00, aesKey, KeyType.AES128);
    break;
  // ... other commands
}
```

### 4. Result Logging

All command executions are logged:

```dart
await FirebaseFirestore.instance
    .collection('command_logs')
    .add({
      'token_id': tagId,
      'command': commandType,
      'executed_at': FieldValue.serverTimestamp(),
      'success': true,
    });
```

## Security Considerations

1. **Authentication**: Only authenticated users can execute commands
2. **Authorization**: Admin commands require admin privileges
3. **Priority Levels**: 
   - `critical`: Must execute, shows error if fails
   - `high`: Important but can retry later
   - `normal`: Standard operations
   - `low`: Background tasks

4. **Audit Trail**: All commands are logged with timestamps and user IDs
5. **Failure Handling**: Critical commands that fail are prominently displayed

## Use Cases

### Mass Security Update
```typescript
// Upgrade all DES tokens to AES
await batchUpgradeEncryption();
```

### Lost Token Recovery
```typescript
// User reports token stolen
await emergencyLockdownToken('TOKEN_UID', 'reported_stolen');
```

### Proactive Key Rotation
```typescript
// Rotate keys older than 90 days
const oldTokens = await getTokensWithOldKeys();
for (const token of oldTokens) {
  await queueServerCommand(token.uid, {
    type: 'rotate_master_key',
    priority: 'normal'
  });
}
```

## Implementation Status

- ✅ Command execution framework in Flutter app
- ✅ Cloud Functions for queueing commands
- ✅ Basic command types defined
- 🔄 DESFire-specific implementations (commented)
- 📋 TODO: Admin UI for command management
- 📋 TODO: Command scheduling and retry logic
- 📋 TODO: Real device testing

## Testing Commands

To test server commands without Firebase:

1. Set `serverCommand` variable in `main.dart`:
```dart
Map<String, dynamic>? serverCommand = {
  'type': 'upgrade_des_to_aes',
  'priority': 'high',
  'params': {'backup_data': true}
};
```

2. Scan a token to see the command execute

3. Check the UI for success/failure messages

## Future Enhancements

1. **Command Scheduling**: Execute commands at specific times
2. **Conditional Commands**: Only execute if certain conditions are met
3. **Command Chaining**: Execute multiple commands in sequence
4. **Offline Queue**: Store commands for offline execution
5. **Push Notifications**: Alert users of pending critical commands 