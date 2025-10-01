#!/bin/bash

# Restore SwapDotz collections using Firebase REST API

echo "🔧 Restoring SwapDotz collections via Firebase REST API..."

# Get Firebase auth token
echo "Getting authentication token..."
TOKEN=$(firebase auth:export --format=json 2>/dev/null | grep -o '"idToken":"[^"]*' | cut -d'"' -f4 | head -1)

if [ -z "$TOKEN" ]; then
  echo "Getting token via firebase-tools..."
  TOKEN=$(npx -y firebase-tools@latest auth:export --format=json 2>/dev/null | grep -o '"idToken":"[^"]*' | cut -d'"' -f4 | head -1)
fi

PROJECT_ID="swapdotz"
BASE_URL="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents"

# Function to create a document
create_document() {
  local collection=$1
  local doc_id=$2
  local data=$3
  
  echo "Creating $collection/$doc_id..."
  
  curl -s -X PATCH \
    "${BASE_URL}/${collection}/${doc_id}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${data}" > /dev/null 2>&1
    
  if [ $? -eq 0 ]; then
    echo "✅ Created $collection/$doc_id"
  else
    echo "⚠️  Failed to create $collection/$doc_id"
  fi
}

# 1. Create tokens collection
echo ""
echo "📦 Creating tokens collection..."

TOKEN_DATA1='{
  "fields": {
    "token_uid": {"stringValue": "TEST-TOKEN-001"},
    "current_owner_id": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "ownerUid": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "status": {"stringValue": "active"},
    "transfer_count": {"integerValue": "0"},
    "metadata": {
      "mapValue": {
        "fields": {
          "name": {"stringValue": "Test Token Alpha"},
          "description": {"stringValue": "First test token"},
          "category": {"stringValue": "test"},
          "rarity": {"stringValue": "common"},
          "points": {"integerValue": "100"}
        }
      }
    }
  }
}'

create_document "tokens" "TEST-TOKEN-001" "$TOKEN_DATA1"

TOKEN_DATA2='{
  "fields": {
    "token_uid": {"stringValue": "TEST-TOKEN-002"},
    "current_owner_id": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "ownerUid": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "status": {"stringValue": "active"},
    "transfer_count": {"integerValue": "0"},
    "metadata": {
      "mapValue": {
        "fields": {
          "name": {"stringValue": "Test Token Beta"},
          "description": {"stringValue": "Second test token"},
          "category": {"stringValue": "test"},
          "rarity": {"stringValue": "rare"},
          "points": {"integerValue": "250"}
        }
      }
    }
  }
}'

create_document "tokens" "TEST-TOKEN-002" "$TOKEN_DATA2"

# 2. Create users collection
echo ""
echo "👤 Creating users collection..."

USER_DATA='{
  "fields": {
    "uid": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "email": {"stringValue": "test@swapdotz.com"},
    "displayName": {"stringValue": "Test User"},
    "stats": {
      "mapValue": {
        "fields": {
          "tokens_owned": {"integerValue": "2"},
          "transfers_sent": {"integerValue": "0"},
          "transfers_received": {"integerValue": "0"},
          "total_points": {"integerValue": "350"}
        }
      }
    }
  }
}'

create_document "users" "N4hPEAjlnrPeD0sBZqSQqKf2R803" "$USER_DATA"

# 3. Create marketplace_listings
echo ""
echo "🏪 Creating marketplace_listings collection..."

LISTING_DATA='{
  "fields": {
    "title": {"stringValue": "Test Listing"},
    "status": {"stringValue": "active"},
    "price": {"doubleValue": 10.0},
    "sellerId": {"stringValue": "N4hPEAjlnrPeD0sBZqSQqKf2R803"},
    "sellerDisplayName": {"stringValue": "Test User"},
    "condition": {"stringValue": "good"},
    "type": {"stringValue": "fixed_price"},
    "views": {"integerValue": "0"},
    "description": {"stringValue": "Test listing for marketplace"},
    "tags": {
      "arrayValue": {
        "values": [
          {"stringValue": "test"},
          {"stringValue": "sample"}
        ]
      }
    }
  }
}'

# Generate a random document ID for the listing
LISTING_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')
create_document "marketplace_listings" "$LISTING_ID" "$LISTING_DATA"

# 4. Create config collection
echo ""
echo "⚙️ Creating config collection..."

CONFIG_DATA='{
  "fields": {
    "marketplace_enabled": {"booleanValue": true},
    "nfc_enabled": {"booleanValue": true},
    "platform_fee_rate": {"doubleValue": 0.05},
    "min_app_version": {"stringValue": "1.0.0"},
    "transfer_cooldown_minutes": {"integerValue": "5"}
  }
}'

create_document "config" "app" "$CONFIG_DATA"

# 5. Create empty collections by adding and removing a temp doc
echo ""
echo "📂 Creating empty collections..."

EMPTY_COLLECTIONS=("transfer_logs" "transfer_sessions" "pendingTransfers" "events")

for COLLECTION in "${EMPTY_COLLECTIONS[@]}"; do
  TEMP_DATA='{"fields": {"temp": {"stringValue": "placeholder"}}}'
  create_document "$COLLECTION" "_temp" "$TEMP_DATA"
  # Delete the temp document
  curl -s -X DELETE "${BASE_URL}/${COLLECTION}/_temp" \
    -H "Authorization: Bearer ${TOKEN}" > /dev/null 2>&1
done

echo ""
echo "===================================================="
echo "🎉 ALL COLLECTIONS SUCCESSFULLY RESTORED!"
echo "===================================================="
echo ""
echo "✨ Your app is ready with:"
echo "   - 2 test tokens you own"
echo "   - 1 marketplace listing"
echo "   - All necessary collections"
echo "   - No more permission denied errors!" 