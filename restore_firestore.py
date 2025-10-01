#!/usr/bin/env python3
"""
Restore SwapDotz Firestore collections using Firebase CLI authentication
"""

import subprocess
import sys
import json
from datetime import datetime

# Check if required package is installed
try:
    from google.cloud import firestore
except ImportError:
    print("Installing google-cloud-firestore...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "google-cloud-firestore"])
    from google.cloud import firestore

def restore_collections():
    print("🔧 Restoring SwapDotz collections...")
    print("=" * 50)
    
    # Initialize Firestore client with project ID
    db = firestore.Client(project='swapdotz')
    
    try:
        # 1. Create tokens collection
        print("\n📦 Creating tokens collection...")
        tokens_ref = db.collection('tokens')
        
        token1 = {
            'token_uid': 'TEST-TOKEN-001',
            'current_owner_id': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'ownerUid': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'previous_owners': [],
            'created_at': firestore.SERVER_TIMESTAMP,
            'last_transfer_at': firestore.SERVER_TIMESTAMP,
            'metadata': {
                'name': 'Test Token Alpha',
                'description': 'First test token',
                'category': 'test',
                'rarity': 'common',
                'points': 100
            },
            'status': 'active',
            'transfer_count': 0
        }
        tokens_ref.document('TEST-TOKEN-001').set(token1)
        print("✅ Created TEST-TOKEN-001")
        
        token2 = {
            'token_uid': 'TEST-TOKEN-002',
            'current_owner_id': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'ownerUid': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'previous_owners': [],
            'created_at': firestore.SERVER_TIMESTAMP,
            'last_transfer_at': firestore.SERVER_TIMESTAMP,
            'metadata': {
                'name': 'Test Token Beta',
                'description': 'Second test token',
                'category': 'test',
                'rarity': 'rare',
                'points': 250
            },
            'status': 'active',
            'transfer_count': 0
        }
        tokens_ref.document('TEST-TOKEN-002').set(token2)
        print("✅ Created TEST-TOKEN-002")
        
        # 2. Create users collection
        print("\n👤 Creating users collection...")
        users_ref = db.collection('users')
        
        user = {
            'uid': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'email': 'test@swapdotz.com',
            'displayName': 'Test User',
            'created_at': firestore.SERVER_TIMESTAMP,
            'last_login': firestore.SERVER_TIMESTAMP,
            'stats': {
                'tokens_owned': 2,
                'transfers_sent': 0,
                'transfers_received': 0,
                'total_points': 350
            },
            'preferences': {
                'notifications_enabled': True,
                'theme': 'dark'
            }
        }
        users_ref.document('N4hPEAjlnrPeD0sBZqSQqKf2R803').set(user)
        print("✅ Created user profile")
        
        # 3. Create marketplace_listings collection
        print("\n🏪 Creating marketplace_listings collection...")
        listings_ref = db.collection('marketplace_listings')
        
        listing1 = {
            'tokenId': 'TEST-TOKEN-002',
            'sellerId': 'N4hPEAjlnrPeD0sBZqSQqKf2R803',
            'sellerDisplayName': 'Test User',
            'title': 'Rare Test Token Beta',
            'description': 'This is a rare test token available for trade',
            'price': 99.99,
            'condition': 'mint',
            'tags': ['test', 'rare', 'collectible'],
            'status': 'active',
            'type': 'fixed_price',
            'createdAt': firestore.SERVER_TIMESTAMP,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            'views': 0,
            'favorites': 0,
            'images': [],
            'location': 'Test Location',
            'shippingAvailable': False,
            'metadata': {
                'rarity': 'rare',
                'points': 250
            }
        }
        listings_ref.add(listing1)
        print("✅ Created listing 1")
        
        listing2 = {
            'tokenId': 'TEST-TOKEN-003',
            'sellerId': 'test-seller-2',
            'sellerDisplayName': 'Another Seller',
            'title': 'Common Test Token',
            'description': 'A common token for testing',
            'price': 25.00,
            'condition': 'good',
            'tags': ['test', 'common', 'starter'],
            'status': 'active',
            'type': 'auction',
            'createdAt': firestore.SERVER_TIMESTAMP,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            'views': 5,
            'favorites': 1,
            'images': [],
            'location': 'Test City',
            'shippingAvailable': True,
            'metadata': {
                'rarity': 'common',
                'points': 50
            }
        }
        listings_ref.add(listing2)
        print("✅ Created listing 2")
        
        # 4. Create config collection
        print("\n⚙️ Creating config collection...")
        config_ref = db.collection('config')
        
        config = {
            'marketplace_enabled': True,
            'nfc_enabled': True,
            'min_app_version': '1.0.0',
            'platform_fee_rate': 0.05,
            'transfer_cooldown_minutes': 5,
            'updated_at': firestore.SERVER_TIMESTAMP
        }
        config_ref.document('app').set(config)
        print("✅ Created app config")
        
        # 5. Create empty collections
        print("\n📂 Creating empty collections...")
        empty_collections = [
            'transfer_logs',
            'transfer_sessions',
            'pendingTransfers',
            'marketplace_profiles',
            'marketplace_offers',
            'marketplace_transactions',
            'user_favorites',
            'offers',
            'events'
        ]
        
        for collection_name in empty_collections:
            # Create a temporary document then delete it to ensure collection exists
            temp_ref = db.collection(collection_name).document('_temp')
            temp_ref.set({'created': firestore.SERVER_TIMESTAMP})
            temp_ref.delete()
            print(f"✅ Created {collection_name}")
        
        print("\n" + "=" * 50)
        print("🎉 ALL COLLECTIONS SUCCESSFULLY RESTORED!")
        print("=" * 50)
        print("\n✨ Your app is ready with:")
        print("   - 2 test tokens you own")
        print("   - 2 marketplace listings to browse")
        print("   - All necessary collections for NFC & marketplace")
        print("   - No more permission denied errors!")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("\nTroubleshooting:")
        print("1. Make sure you're logged in: firebase login")
        print("2. Or try: gcloud auth application-default login")
        return False
    
    return True

if __name__ == "__main__":
    restore_collections() 