# SwapDotz Firebase Backend

This directory contains the Firebase backend infrastructure for the SwapDotz NFC token ownership platform.

## Architecture Overview

The backend consists of:

1. **Firestore Database** - Stores token ownership, transfer sessions, and user data
2. **Cloud Functions** - Handles secure ownership transfers and cryptographic validation
3. **Firebase Authentication** - Manages user identity (starting with anonymous auth)
4. **Security Rules** - Enforces access control and data integrity

## Data Schema

### Collections

#### `tokens`
Stores NFC token information and ownership:
```typescript
{
  uid: string;                    // Token's unique ID from NFC chip
  current_owner_id: string;       // Firebase Auth UID of current owner
  previous_owners: string[];      // Array of previous owner IDs
  key_hash: string;              // Hash of current AES key (never store actual key)
  created_at: Timestamp;         // When first registered
  last_transfer_at: Timestamp;   // Last ownership change
  metadata: {
    travel_stats: {
      countries_visited: string[];
      cities_visited: string[];
      total_distance_km: number;
      last_location?: { lat, lng, timestamp };
    };
    leaderboard_points: number;
    series?: string;
    edition?: string;
    rarity?: 'common' | 'uncommon' | 'rare' | 'legendary';
  }
}
```

#### `transfer_sessions`
Temporary sessions for ownership transfers:
```typescript
{
  session_id: string;            // Unique session identifier
  token_uid: string;             // Token being transferred
  from_user_id: string;          // Current owner initiating transfer
  to_user_id?: string;           // Optional: specific recipient
  expires_at: Timestamp;         // Session expiration (default: 5 min)
  status: 'pending' | 'completed' | 'expired' | 'cancelled';
  created_at: Timestamp;
  challenge_data?: {
    challenge: string;           // Cryptographic challenge
    expected_response_hash: string;
  }
}
```

#### `users`
Extended user profiles:
```typescript
{
  uid: string;                   // Firebase Auth UID
  display_name?: string;
  avatar_url?: string;
  stats: {
    tokens_owned: number;
    tokens_transferred_out: number;
    tokens_received: number;
    total_leaderboard_points: number;
  };
  created_at: Timestamp;
  last_active_at: Timestamp;
}
```

#### `transfer_logs`
Permanent record of completed transfers:
```typescript
{
  id: string;
  token_uid: string;
  from_user_id: string;
  to_user_id: string;
  session_id: string;
  completed_at: Timestamp;
  metadata?: {
    location?: { lat, lng };
    device_info?: string;
  }
}
```

## Cloud Functions

### `registerToken`
Registers a new token when first scanned.
```typescript
// Request
{
  token_uid: string;
  key_hash: string;
  metadata?: object;
}

// Response
{
  success: boolean;
  token_uid: string;
}
```

### `initiateTransfer`
Creates a transfer session for the current owner.
```typescript
// Request
{
  token_uid: string;
  to_user_id?: string;            // Optional: specific recipient
  session_duration_minutes?: number; // Default: 5
}

// Response
{
  session_id: string;
  expires_at: string;             // ISO timestamp
  challenge?: string;             // For cryptographic verification
}
```

### `completeTransfer`
Completes ownership transfer with new key.
```typescript
// Request
{
  session_id: string;
  challenge_response?: string;    // Response to challenge
  new_key_hash: string;          // Hash after rekey operation
}

// Response
{
  success: boolean;
  new_owner_id: string;
  transfer_log_id: string;
}
```

### `validateChallenge`
Validates challenge response without completing transfer.
```typescript
// Request
{
  session_id: string;
  challenge_response: string;
}

// Response
{
  valid: boolean;
  session_id: string;
}
```

### `cleanupExpiredSessions`
Scheduled function that runs every 15 minutes to mark expired sessions.

## Security Model

### Authentication
- Users authenticate anonymously (for now)
- Each user gets a unique Firebase Auth UID
- Future: Email/social login support

### Authorization Rules
1. **Tokens**: 
   - Any authenticated user can read
   - Only Cloud Functions can write (no direct modifications)

2. **Transfer Sessions**:
   - Users can read sessions they're involved in
   - Only Cloud Functions can create/update

3. **Users**:
   - Any authenticated user can read profiles
   - Users can update their own profile (except stats)

4. **Transfer Logs**:
   - Users can read logs they're involved in
   - Only Cloud Functions can write

### Transfer Security
1. Only current owner can initiate transfer
2. Time-bound sessions (default: 5 minutes)
3. Optional cryptographic challenge-response
4. Atomic transactions prevent race conditions
5. Key rotation on every transfer

## Setup Instructions

### Prerequisites
- Node.js 18+
- Firebase CLI (`npm install -g firebase-tools`)
- Firebase project created

### Installation

1. **Install dependencies**:
```bash
cd firebase/functions
npm install
```

2. **Configure Firebase**:
```bash
firebase login
firebase use --add
# Select your Firebase project
```

3. **Deploy everything**:
```bash
# From firebase directory
firebase deploy
```

Or deploy individually:
```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions
```

### Local Development

1. **Start emulators**:
```bash
firebase emulators:start
```

2. **Run functions locally**:
```bash
cd functions
npm run serve
```

## Flutter Integration

See `flutter_integration.dart` for complete examples. Basic flow:

```dart
// 1. Authenticate
final user = await SwapDotzFirebaseService.authenticateAnonymously();

// 2. Register new token
await SwapDotzFirebaseService.registerToken(
  tokenUid: 'ABC123',
  keyHash: 'hashed_key',
);

// 3. Transfer ownership
// Sender initiates:
final transfer = await SwapDotzFirebaseService.initiateTransfer(
  tokenUid: 'ABC123',
);

// Receiver completes:
final result = await SwapDotzFirebaseService.completeTransfer(
  sessionId: transfer.sessionId,
  newKeyHash: 'new_hashed_key',
);
```

## Environment Variables

Cloud Functions use Firebase's built-in authentication. No additional environment variables needed for basic operation.

For production, consider setting:
```bash
firebase functions:config:set app.session_duration_minutes="5"
```

## Monitoring & Debugging

1. **View logs**:
```bash
firebase functions:log
```

2. **Firestore Console**: Monitor data and test security rules
3. **Cloud Functions Console**: View execution metrics and errors

## Future Enhancements

1. **Enhanced Authentication**:
   - Email/password login
   - Social auth providers
   - Multi-factor authentication

2. **Advanced Features**:
   - Token trading/marketplace
   - Achievement system
   - Social features (following, messaging)
   - Location-based challenges

3. **Analytics**:
   - Transfer patterns
   - User engagement metrics
   - Token journey visualization

4. **Security**:
   - Rate limiting
   - Fraud detection
   - Additional cryptographic proofs

## Security Considerations

1. **Never store actual AES keys** - only hashes
2. **Validate all inputs** in Cloud Functions
3. **Use transactions** for atomic operations
4. **Implement rate limiting** for production
5. **Monitor for suspicious patterns**
6. **Regular security audits** of rules and functions

## Support

For issues or questions about the Firebase backend, please refer to:
- Firebase Documentation: https://firebase.google.com/docs
- Cloud Functions Guide: https://firebase.google.com/docs/functions
- Firestore Security Rules: https://firebase.google.com/docs/firestore/security/get-started 