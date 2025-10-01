# Transfer Security Fixes

## Issues Addressed

### Issue 1: Permission Denied for Receivers
**Problem**: Receivers couldn't read token documents during transfers, causing "unregistered SwapDot" errors.
**Fix**: Updated Firestore security rules to allow any authenticated user to read a token if there's an active `pendingTransfer` for it.

### Issue 2: Old Owners Could Re-initiate Transfers
**Problem**: After a receiver claimed a token, the original owner could still create new transfers because:
1. The `pendingTransfer` document remained in 'COMMITTED' state instead of being deleted
2. The frontend didn't properly check for completed transfers
3. The backend didn't handle state transitions properly

### Issue 3: Stale Token Data in Frontend
**Problem**: The frontend was using cached token ownership data from the initial NFC scan, not checking for updated ownership after transfers completed. This allowed the old owner to still initiate transfers even after losing ownership.
**Fix**: Frontend now re-fetches the latest token data from Firebase before any ownership-dependent operations to ensure decisions are made with real-time data.

**Fixes Implemented**:

## Backend Fixes (Cloud Functions)

### 1. `initiateSecureTransfer` Function
- Now properly checks the state of existing `pendingTransfer` documents
- Prevents creating new transfers if one is already 'COMMITTED'
- Allows owners to overwrite their own 'OPEN' transfers
- Cleans up any legacy `transfer_sessions` when creating secure transfers
- Properly validates ownership before allowing transfer initiation

### 2. `finalizeSecureTransfer` Function  
- **Deletes** the `pendingTransfer` document after successful completion (instead of leaving it as 'COMMITTED')
- Also cancels any legacy `transfer_sessions` for the same token
- Ensures complete cleanup of all transfer records

## Frontend Fixes (Flutter)

### 1. `_handleExistingToken` Function
- Added check for 'COMMITTED' state transfers
- Shows appropriate error message if transfer already completed
- Validates that pending transfer is from current user before allowing overwrite
- Prevents initiating transfers if another user has an active transfer
- **Re-fetches latest token data** before ownership checks to prevent using stale data
- Ensures ownership verification uses real-time data from Firebase, not cached data from initial scan

## Security Rules Fixes

### 1. Token Read Permissions
Added helper function and permission:
```javascript
function hasPendingTransfer(tokenId) {
  return exists(/databases/$(database)/documents/pendingTransfers/$(tokenId));
}

allow read: if isAuthed() && (
  // ... existing conditions ...
  hasPendingTransfer(tokenId)  // NEW: Anyone can read if transfer pending
);
```

## Testing the Fixes

### Test Case 1: Basic Transfer Flow
1. **Gifter** (as "Gifter"): Scan token → Initiate transfer ✅
2. **Receiver** (as "receiver"): Scan token → Complete transfer ✅
3. **Gifter** (as "Gifter"): Scan token again → Should see "You no longer own this token" ✅

### Test Case 2: Overwrite Own Transfer
1. **Gifter**: Initiate transfer
2. **Gifter**: Scan again before receiver claims → Can create new transfer session ✅

### Test Case 3: Cannot Interfere with Others' Transfers
1. **Owner A**: Initiates transfer
2. **Owner B**: Cannot initiate transfer for same token ✅

## State Management

### Transfer States
- **No `pendingTransfer`**: No active transfer
- **`pendingTransfer` with state 'OPEN'**: Active transfer waiting for receiver
- **`pendingTransfer` deleted**: Transfer completed successfully
- **`pendingTransfer` with state 'EXPIRED'**: Transfer expired, can be overwritten

### Ownership Verification
The system now properly verifies ownership at multiple levels:
1. **Backend**: Checks `ownerUid` field matches authenticated user
2. **Frontend**: Validates against `currentOwnerId` from token document
3. **Cleanup**: Removes all transfer records after successful completion

## Deployment Commands

```bash
# Deploy security rules
cd firebase
firebase deploy --only firestore:rules

# Deploy Cloud Functions
cd functions
firebase deploy --only functions:initiateSecureTransfer,functions:finalizeSecureTransfer
```

## Key Improvements
1. ✅ Complete cleanup of transfer records after completion
2. ✅ Proper state management preventing duplicate transfers
3. ✅ Clear error messages for all edge cases
4. ✅ Backward compatibility with legacy transfer system
5. ✅ Atomic operations ensuring data consistency 