const admin = require('firebase-admin');

// Initialize Firebase Admin with your service account
// You'll need to download your service account key from Firebase Console
// and place it in the firebase folder
try {
  const serviceAccount = require('./firebase/swapdotz-firebase-adminsdk-kigsy-25cf6b5100.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'swapdotz'
  });
} catch (error) {
  console.log('⚠️  Service account file not found. Using default credentials.');
  console.log('To set up collections, download your service account key from:');
  console.log('https://console.firebase.google.com/project/swapdotz/settings/serviceaccounts/adminsdk');
  
  // Try default initialization
  admin.initializeApp({
    projectId: 'swapdotz'
  });
}

const db = admin.firestore();

async function setupMarketplaceCollections() {
  console.log('🚀 Setting up marketplace collections...');
  
  try {
    // 1. Create sample tokens (required for creating listings)
    console.log('📦 Creating sample tokens...');
    const tokensData = [
      {
        id: 'token-001',
        name: 'Vintage Baseball Card',
        description: 'Rare 1989 Ken Griffey Jr. rookie card',
        current_owner_id: 'user-123', // This should match a real user ID
        ownerUid: 'user-123',
        metadata: {
          sport: 'baseball',
          year: 1989,
          player: 'Ken Griffey Jr.',
          condition: 'mint'
        },
        created_at: admin.firestore.Timestamp.now(),
        last_transfer_at: admin.firestore.Timestamp.now()
      },
      {
        id: 'token-002', 
        name: 'Pokemon Card Collection',
        description: 'First edition Charizard holographic card',
        current_owner_id: 'user-456',
        ownerUid: 'user-456',
        metadata: {
          game: 'pokemon',
          edition: 'first',
          rarity: 'holographic'
        },
        created_at: admin.firestore.Timestamp.now(),
        last_transfer_at: admin.firestore.Timestamp.now()
      },
      {
        id: 'token-003',
        name: 'Limited Edition Sneakers',
        description: 'Nike Air Jordan 1 Retro High OG',
        current_owner_id: 'user-789',
        ownerUid: 'user-789',
        metadata: {
          brand: 'Nike',
          model: 'Air Jordan 1',
          size: '10.5',
          colorway: 'Bred'
        },
        created_at: admin.firestore.Timestamp.now(),
        last_transfer_at: admin.firestore.Timestamp.now()
      }
    ];

    for (const token of tokensData) {
      await db.collection('tokens').doc(token.id).set(token);
    }

    // 2. Create marketplace profiles
    console.log('👤 Creating marketplace profiles...');
    const profilesData = [
      {
        userId: 'user-123',
        displayName: 'SportCards_Collector',
        email: 'collector@example.com',
        rating: 4.8,
        totalSales: 15,
        totalPurchases: 23,
        joinedAt: admin.firestore.Timestamp.now(),
        verified: true,
        badges: ['verified_seller', 'top_buyer']
      },
      {
        userId: 'user-456',
        displayName: 'PokemonMaster99',
        email: 'pokemon@example.com', 
        rating: 4.9,
        totalSales: 8,
        totalPurchases: 12,
        joinedAt: admin.firestore.Timestamp.now(),
        verified: true,
        badges: ['pokemon_expert']
      },
      {
        userId: 'user-789',
        displayName: 'SneakerHead_NYC',
        email: 'sneakers@example.com',
        rating: 4.7,
        totalSales: 32,
        totalPurchases: 5,
        joinedAt: admin.firestore.Timestamp.now(),
        verified: true,
        badges: ['sneaker_expert', 'power_seller']
      }
    ];

    for (const profile of profilesData) {
      await db.collection('marketplace_profiles').doc(profile.userId).set(profile);
    }

    // 3. Create sample marketplace listings
    console.log('🏪 Creating sample marketplace listings...');
    const listingsData = [
      {
        tokenId: 'token-001',
        sellerId: 'user-123',
        sellerDisplayName: 'SportCards_Collector',
        title: 'Vintage 1989 Ken Griffey Jr. Rookie Card',
        description: 'Mint condition rookie card of the legendary Ken Griffey Jr. Professionally graded and authenticated. Perfect for any baseball card collection.',
        price: 450.00,
        condition: 'mint',
        tags: ['baseball', 'vintage', 'rookie', 'graded'],
        status: 'active',
        type: 'fixed_price',
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        views: 127,
        favorites: 23,
        images: [], // Image upload not implemented yet
        location: 'Seattle, WA',
        shippingAvailable: true,
        shippingCost: 15.00,
        metadata: {
          grade: 'PSA 10',
          certified: true
        }
      },
      {
        tokenId: 'token-002',
        sellerId: 'user-456', 
        sellerDisplayName: 'PokemonMaster99',
        title: 'First Edition Charizard Holographic',
        description: 'The holy grail of Pokemon cards! First edition Base Set Charizard in excellent condition. This is a must-have for any serious Pokemon collector.',
        price: 2500.00,
        condition: 'near_mint',
        tags: ['pokemon', 'charizard', 'first_edition', 'holographic'],
        status: 'active',
        type: 'fixed_price', 
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        views: 892,
        favorites: 156,
        images: [],
        location: 'Los Angeles, CA',
        shippingAvailable: true,
        shippingCost: 25.00,
        metadata: {
          set: 'Base Set',
          card_number: '4/102'
        }
      },
      {
        tokenId: 'token-003',
        sellerId: 'user-789',
        sellerDisplayName: 'SneakerHead_NYC',
        title: 'Nike Air Jordan 1 Retro High OG "Bred"',
        description: 'Classic colorway in size 10.5. Worn only a few times, excellent condition. Comes with original box and all accessories.',
        price: 180.00,
        condition: 'good',
        tags: ['nike', 'jordan', 'bred', 'retro'],
        status: 'active',
        type: 'fixed_price',
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        views: 234,
        favorites: 45,
        images: [],
        location: 'New York, NY', 
        shippingAvailable: true,
        shippingCost: 20.00,
        metadata: {
          size: '10.5',
          brand: 'Nike',
          style_code: '555088-062'
        }
      }
    ];

    for (let i = 0; i < listingsData.length; i++) {
      await db.collection('marketplace_listings').doc(`listing-${i + 1}`).set(listingsData[i]);
    }

    // 4. Create config collection if it doesn't exist
    console.log('⚙️ Setting up config collection...');
    await db.collection('config').doc('app').set({
      marketplace_enabled: true,
      platform_fee_rate: 0.05,
      min_listing_price: 1.00,
      max_listing_price: 10000.00,
      supported_currencies: ['usd'],
      updated_at: admin.firestore.Timestamp.now()
    }, { merge: true });

    // 5. Initialize user_favorites collection structure
    console.log('❤️ Setting up user favorites structure...');
    // This creates the collection structure - users will add their own favorites
    await db.collection('user_favorites').doc('_structure').set({
      description: 'This collection stores user favorite listings',
      example_structure: {
        userId: 'string',
        listingIds: ['array', 'of', 'listing', 'ids'],
        updatedAt: 'timestamp'
      },
      created_at: admin.firestore.Timestamp.now()
    });

    console.log('✅ Successfully set up all marketplace collections!');
    console.log('\n📊 Collections created:');
    console.log('   • tokens (3 sample tokens)');
    console.log('   • marketplace_profiles (3 sample profiles)'); 
    console.log('   • marketplace_listings (3 sample listings)');
    console.log('   • config (app configuration)');
    console.log('   • user_favorites (structure only)');
    console.log('\n🚀 Your marketplace is now ready to use!');
    console.log('   • Users can browse the 3 sample listings');
    console.log('   • Users can make offers on listings');  
    console.log('   • Users can create new listings (if they own tokens)');
    console.log('\n💡 To create more tokens for testing, use the token creation flow in your app');

  } catch (error) {
    console.error('❌ Error setting up collections:', error);
  }
  
  process.exit(0);
}

setupMarketplaceCollections(); 