// Fix permission denied error by creating a test document
// Run with: GOOGLE_APPLICATION_CREDENTIALS=path/to/key.json node fix_permission_denied.js
// OR: FIREBASE_TOKEN="your-token" node fix_permission_denied.js

const admin = require('firebase-admin');

// Initialize with application default credentials
admin.initializeApp({
  projectId: 'swapdotz'
});

const db = admin.firestore();

async function fixPermissionDenied() {
  console.log('🔧 Fixing permission denied error...');
  
  try {
    // Create a minimal test document to initialize the collection
    const testDoc = {
      title: 'Initialize Collection',
      status: 'active',
      price: 1,
      sellerId: 'system',
      sellerDisplayName: 'System',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      condition: 'good',
      tags: [],
      type: 'fixed_price',
      views: 0,
      favorites: 0,
      images: [],
      metadata: {},
      tokenId: 'init-token'
    };
    
    // Create the document
    await db.collection('marketplace_listings').doc('init-doc').set(testDoc);
    
    console.log('✅ Created initialization document');
    
    // Now test if we can query the collection
    const snapshot = await db.collection('marketplace_listings')
      .where('status', '==', 'active')
      .limit(1)
      .get();
    
    console.log(`✅ Query test successful! Found ${snapshot.size} document(s)`);
    console.log('🎉 Permission denied error should be fixed!');
    console.log('\nYou can now:');
    console.log('1. Run your Flutter app');
    console.log('2. Navigate to the marketplace');
    console.log('3. The "permission denied" errors should be gone');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.log('\n💡 Try running with authentication:');
    console.log('   export GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json');
    console.log('   node fix_permission_denied.js');
  }
  
  process.exit(0);
}

fixPermissionDenied(); 