# Transfer Permission Fix

## Issue Description
When a Gifter initiates a secure transfer and a Receiver scans the token, the system was incorrectly showing "unregistered SwapDot" instead of properly handling the transfer.

## Root Cause
The Firebase security rules for the `tokens` collection were too restrictive. They only allowed reading token documents if the user was:
1. The current owner
2. A previous owner
3. An admin

When a receiver (who had never owned the token) tried to scan it during a transfer, they couldn't read the token document from Firebase due to these restrictions. This caused `SwapDotzFirebaseService.getToken(tokenUid)` to return `null`, making the app incorrectly treat it as an unregistered token.

## The Fix
Updated the Firestore security rules in `firebase/firestore.rules` to add a new condition allowing any authenticated user to read a token document if there's an active pending transfer for that token.

### Changes Made:
1. Added a helper function to check for pending transfers:
```javascript
function hasPendingTransfer(tokenId) {
  return exists(/databases/$(database)/documents/pendingTransfers/$(tokenId));
}
```

2. Updated the read permission rule for tokens to include:
```javascript
allow read: if isAuthed() && (
  resource.data.ownerUid == request.auth.uid ||           // Current owner can read
  resource.data.current_owner_id == request.auth.uid ||   // Legacy field support  
  resource.data.previous_owners.hasAny([request.auth.uid]) ||  // Previous owners can read
  request.auth.token.admin == true ||                     // Admins can read all
  hasPendingTransfer(tokenId)                            // Anyone can read if there's a pending transfer
);
```

## Testing the Fix
To verify the fix works:
1. **Gifter** (logged in as "Gifter"): Scan your SwapDot to initiate a secure transfer
2. **Receiver** (logged in as "receiver"): Scan the same SwapDot to receive it
3. The receiver should now properly see the transfer screen instead of "unregistered SwapDot"

## Security Considerations
This change is secure because:
- It only allows reading token data when there's an active transfer session
- The actual transfer completion still requires proper authentication through Cloud Functions
- The pendingTransfers document acts as a temporary permission grant
- Once the transfer completes or expires, the pendingTransfer document is removed, revoking the read permission

## Deployment
The fix has been deployed to production using:
```bash
cd firebase
firebase deploy --only firestore:rules
```

## Related Files
- `firebase/firestore.rules` - The security rules configuration
- `lib/services/secure_transfer_service.dart` - Service handling secure transfers
- `lib/screens/home_screen.dart` - NFC scanning and transfer flow logic 