// Simple script to create a test marketplace listing
// This will create the collection and fix the permission denied error

const admin = require('firebase-admin');
const serviceAccount = require('./firebase/functions/service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'swapdotz'
});

const db = admin.firestore();

async function createTestListing() {
  try {
    // Create a simple test listing
    await db.collection('marketplace_listings').doc('test-listing').set({
      title: 'Test Listing',
      description: 'This is a test listing to initialize the collection',
      price: 10.00,
      status: 'active',
      sellerId: 'test-user',
      sellerDisplayName: 'Test User',
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.Timestamp.now(),
      condition: 'good',
      tags: ['test'],
      type: 'fixed_price',
      views: 0,
      favorites: 0,
      images: [],
      metadata: {}
    });
    
    console.log('✅ Test listing created successfully!');
    console.log('The marketplace_listings collection now exists.');
    console.log('The permission denied error should be fixed.');
  } catch (error) {
    console.error('Error:', error);
  }
  process.exit(0);
}

createTestListing(); 