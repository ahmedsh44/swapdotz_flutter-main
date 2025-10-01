# Token Ownership Debugging for Marketplace

## Issue
User reports that the "Select Token" dropdown in the marketplace shows no SwapDotz, even though they own one.

## From the Logs

### Token Information
- **Token ID**: `04942D1A7D6C80`
- **Owner (from logs)**: `N4hPEAjlnrPeD0sBZqSQqKf2R803`
- **Both fields set**: 
  - `ownerUid`: `N4hPEAjlnrPeD0sBZqSQqKf2R803`
  - `current_owner_id`: `N4hPEAjlnrPeD0sBZqSQqKf2R803`

### Previous Transfer Session
From earlier logs, there was also a different user ID involved:
- **Previous owner**: `W7I0cZvCqHdnadFTP6UBQuDR3N02`

## Debugging Steps Added

1. **Enhanced logging in `getUserTokens()`**:
   - Logs the user ID being queried
   - Shows how many tokens are found
   - Lists each token's owner

2. **Enhanced logging in `create_listing_screen.dart`**:
   - Shows current user ID
   - Shows tokens received from stream
   - Shows active listings that might filter tokens
   - Shows final available tokens

3. **Enhanced logging in `getCurrentUserId()`**:
   - Shows whether user is already authenticated
   - Shows if new anonymous user is created

## Potential Issues

1. **User ID Mismatch**: The current user ID in the app might be different from the owner ID in the database
2. **Index Missing**: Firebase might not have an index for the `ownerUid` field
3. **Token Already Listed**: The token might already have an active listing
4. **Authentication State**: User might be getting a new anonymous ID each time

## Solution Applied

Modified `getUserTokens()` to:
1. Query `current_owner_id` first (which should have an index)
2. Try to also query `ownerUid` with error handling
3. Combine results from both queries
4. Handle errors gracefully

## Next Steps

1. Check the console logs when navigating to the marketplace
2. Verify the current user ID matches the token owner ID
3. Check if there are any active listings for the token
4. Ensure Firebase indexes are properly configured 