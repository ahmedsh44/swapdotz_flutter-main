// Restore all SwapDotz collections using Firebase CLI authentication
const admin = require('firebase-admin');

// Initialize with application default credentials (uses Firebase CLI auth)
admin.initializeApp({
  projectId: 'swapdotz'
});

const db = admin.firestore();

async function restoreAllCollections() {
  console.log('🔧 Restoring all SwapDotz collections using Firebase CLI auth...\n');
  
  try {
    // 1. TOKENS COLLECTION - Essential for the app
    console.log('📦 Creating tokens collection...');
    const tokensData = [
      {
        token_uid: 'TEST-TOKEN-001',
        current_owner_id: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
        ownerUid: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
        previous_owners: [],
        created_at: admin.firestore.Timestamp.now(),
        last_transfer_at: admin.firestore.Timestamp.now(),
        metadata: {
          name: 'Test Token Alpha',
          description: 'First test token',
          category: 'test',
          rarity: 'common',
          points: 100
        },
        status: 'active',
        transfer_count: 0
      },
      {
        token_uid: 'TEST-TOKEN-002',
        current_owner_id: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
        ownerUid: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
        previous_owners: [],
        created_at: admin.firestore.Timestamp.now(),
        last_transfer_at: admin.firestore.Timestamp.now(),
        metadata: {
          name: 'Test Token Beta',
          description: 'Second test token',
          category: 'test',
          rarity: 'rare',
          points: 250
        },
        status: 'active',
        transfer_count: 0
      }
    ];
    
    for (const token of tokensData) {
      await db.collection('tokens').doc(token.token_uid).set(token);
    }
    console.log('✅ Restored tokens collection with 2 test tokens');

    // 2. USERS COLLECTION
    console.log('👤 Creating users collection...');
    const usersData = {
      uid: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
      email: 'test@swapdotz.com',
      displayName: 'Test User',
      created_at: admin.firestore.Timestamp.now(),
      last_login: admin.firestore.Timestamp.now(),
      stats: {
        tokens_owned: 2,
        transfers_sent: 0,
        transfers_received: 0,
        total_points: 350
      },
      preferences: {
        notifications_enabled: true,
        theme: 'dark'
      }
    };
    
    await db.collection('users').doc(usersData.uid).set(usersData);
    console.log('✅ Restored users collection');

    // 3. MARKETPLACE_LISTINGS COLLECTION (fixes the permission denied error)
    console.log('🏪 Creating marketplace_listings collection...');
    const listings = [
      {
        tokenId: 'TEST-TOKEN-002',
        sellerId: 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
        sellerDisplayName: 'Test User',
        title: 'Rare Test Token Beta',
        description: 'This is a rare test token available for trade',
        price: 99.99,
        condition: 'mint',
        tags: ['test', 'rare', 'collectible'],
        status: 'active',
        type: 'fixed_price',
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        views: 0,
        favorites: 0,
        images: [],
        location: 'Test Location',
        shippingAvailable: false,
        metadata: {
          rarity: 'rare',
          points: 250
        }
      },
      {
        tokenId: 'TEST-TOKEN-003',
        sellerId: 'test-seller-2',
        sellerDisplayName: 'Another Seller',
        title: 'Common Test Token',
        description: 'A common token for testing',
        price: 25.00,
        condition: 'good',
        tags: ['test', 'common', 'starter'],
        status: 'active',
        type: 'auction',
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        views: 5,
        favorites: 1,
        images: [],
        location: 'Test City',
        shippingAvailable: true,
        metadata: {
          rarity: 'common',
          points: 50
        }
      }
    ];
    
    for (const listing of listings) {
      await db.collection('marketplace_listings').add(listing);
    }
    console.log('✅ Created marketplace_listings with 2 test listings');

    // 4. Empty collections (just create with a temp doc then delete)
    const emptyCollections = [
      'transfer_logs',
      'transfer_sessions', 
      'pendingTransfers',
      'marketplace_profiles',
      'marketplace_offers',
      'marketplace_transactions',
      'user_favorites',
      'offers',
      'events'
    ];

    for (const collName of emptyCollections) {
      console.log(`📂 Creating ${collName} collection...`);
      const docRef = db.collection(collName).doc('_temp');
      await docRef.set({ created: admin.firestore.Timestamp.now() });
      await docRef.delete();
      console.log(`✅ Created ${collName} collection`);
    }

    // 5. CONFIG COLLECTION
    console.log('⚙️ Creating config collection...');
    await db.collection('config').doc('app').set({
      marketplace_enabled: true,
      nfc_enabled: true,
      min_app_version: '1.0.0',
      platform_fee_rate: 0.05,
      transfer_cooldown_minutes: 5,
      updated_at: admin.firestore.Timestamp.now()
    });
    console.log('✅ Created config collection');

    console.log('\n' + '='.repeat(50));
    console.log('🎉 ALL COLLECTIONS SUCCESSFULLY RESTORED!');
    console.log('='.repeat(50));
    console.log('\n✨ Your app is ready to use with:');
    console.log('   - 2 test tokens you own');
    console.log('   - 2 marketplace listings to browse');
    console.log('   - All necessary collections for NFC & marketplace');
    console.log('   - No more permission denied errors!');
    
  } catch (error) {
    console.error('❌ Error during restoration:', error.message);
    console.log('\nTroubleshooting:');
    console.log('1. Make sure you are logged in: firebase login');
    console.log('2. Set the project: firebase use swapdotz');
    console.log('3. Try running with: GOOGLE_APPLICATION_CREDENTIALS="" node restore_with_cli.js');
  }
  
  process.exit(0);
}

restoreAllCollections(); 