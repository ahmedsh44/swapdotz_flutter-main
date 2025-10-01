# Quick Manual Restore - All Collections

Since we need authentication, here's the fastest way to restore everything manually through the Firebase Console.

## Open Firebase Console
Go to: https://console.firebase.google.com/project/swapdotz/firestore

## Create Each Collection (5 minutes total)

### 1. tokens Collection
- Click "Start collection" → ID: `tokens`
- Document ID: `TEST-TOKEN-001`
- Fields:
  - `token_uid` (string): TEST-TOKEN-001
  - `current_owner_id` (string): N4hPEAjlnrPeD0sBZqSQqKf2R803
  - `ownerUid` (string): N4hPEAjlnrPeD0sBZqSQqKf2R803
  - `status` (string): active
  - `transfer_count` (number): 0
  - `created_at` (timestamp): Now
  - `last_transfer_at` (timestamp): Now
- Save

### 2. users Collection  
- Start collection → ID: `users`
- Document ID: `N4hPEAjlnrPeD0sBZqSQqKf2R803`
- Fields:
  - `uid` (string): N4hPEAjlnrPeD0sBZqSQqKf2R803
  - `email` (string): test@swapdotz.com
  - `displayName` (string): Test User
  - `created_at` (timestamp): Now
- Save

### 3. marketplace_listings Collection (fixes permission denied)
- Start collection → ID: `marketplace_listings`
- Document ID: Auto-ID
- Fields:
  - `title` (string): Test Listing
  - `status` (string): active
  - `price` (number): 10
  - `sellerId` (string): N4hPEAjlnrPeD0sBZqSQqKf2R803
  - `sellerDisplayName` (string): Test User
  - `condition` (string): good
  - `type` (string): fixed_price
  - `views` (number): 0
  - `createdAt` (timestamp): Now
- Save

### 4. config Collection
- Start collection → ID: `config`
- Document ID: `app`
- Fields:
  - `marketplace_enabled` (boolean): true
  - `nfc_enabled` (boolean): true
  - `platform_fee_rate` (number): 0.05
- Save

### 5. Empty Collections (just create, no documents needed)
- Start collection → ID: `transfer_logs` → Cancel (creates empty collection)
- Start collection → ID: `transfer_sessions` → Cancel
- Start collection → ID: `pendingTransfers` → Cancel
- Start collection → ID: `events` → Cancel

## That's it! 
Your app should now work perfectly with all necessary collections restored. 