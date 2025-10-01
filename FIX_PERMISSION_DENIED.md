# Fix "Permission Denied" Error - Quick Solution

The "permission denied" error is happening because the `marketplace_listings` collection doesn't exist yet, and Firestore sometimes returns permission errors when querying empty/non-existent collections.

## Quick Fix (Via Firebase Console - 2 minutes)

1. **Open Firebase Console**:
   ```
   https://console.firebase.google.com/project/swapdotz/firestore
   ```

2. **Create the Collection**:
   - Click "Start collection"
   - Collection ID: `marketplace_listings`
   - Click "Next"

3. **Create a Test Document**:
   - Document ID: Click "Auto-ID" or use `test-doc`
   - Add these fields:
     - `title` (string): "Test Listing"
     - `status` (string): "active"
     - `price` (number): 10
     - `sellerId` (string): "test-user"
     - `sellerDisplayName` (string): "Test User"
     - `condition` (string): "good"
     - `type` (string): "fixed_price"
     - `views` (number): 0
     - `favorites` (number): 0
     - `tags` (array): Click "Add item" and add "test"
     - `createdAt` (timestamp): Click the clock icon
     - `updatedAt` (timestamp): Click the clock icon
   - Click "Save"

4. **Test Your App**:
   - Run your Flutter app
   - Navigate to the marketplace
   - The "permission denied" errors should be gone!
   - You should see "Test Listing" in the marketplace

## Why This Works

- Creates the collection that the queries are looking for
- Satisfies Firestore's requirement for at least one document
- The security rules already allow public read access (`allow read: if true`)
- Once the collection exists, the queries work properly

## Optional: Clean Up

After verifying the fix works, you can:
1. Delete the test document if you want
2. Create real listings through the app
3. The collection will continue to work even if empty

That's it! This simple fix should resolve the stubborn permission denied error. 