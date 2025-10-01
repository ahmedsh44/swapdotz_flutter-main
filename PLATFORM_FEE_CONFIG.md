# SwapDotz Platform Fee Configuration

## Current Settings

**Platform Fee**: 5% of transaction value
**Implementation**: Server-side only (Cloud Functions)
**Security**: Cannot be modified by client applications

## Where to Change the Fee

### 1. Primary Configuration
**File**: `firebase/functions/src/payments.ts`
```typescript
// Platform fee percentage (e.g., 5% = 0.05)
const PLATFORM_FEE_RATE = 0.05;

// Usage in payment intent creation:
const platformFee = Math.round(amount * PLATFORM_FEE_RATE);
```

### 2. Documentation Updates
When changing the fee, update these files:
- `PAYMENT_INTEGRATION_GUIDE.md` (lines 114, 349)
- `MARKETPLACE_STATUS.md` (revenue model section)
- This file (`PLATFORM_FEE_CONFIG.md`)

## Revenue Calculation

### Current 5% Fee Structure
```
Transaction: $100
├── Buyer pays: $100.00 (100%)
├── Platform fee: $5.00 (5%)
├── Stripe fees: ~$3.40 (3.4% + 30¢)
├── Seller receives: $95.00 (95%)
└── Net platform profit: ~$1.60 (1.6%)
```

### Alternative Fee Scenarios

#### 3% Platform Fee
```
Transaction: $100
├── Platform fee: $3.00 (3%)
├── Stripe fees: ~$3.40 (3.4% + 30¢)
├── Seller receives: $97.00 (97%)
└── Net platform profit: -$0.40 (-0.4%) ❌ LOSS
```

#### 7% Platform Fee
```
Transaction: $100
├── Platform fee: $7.00 (7%)
├── Stripe fees: ~$3.40 (3.4% + 30¢)
├── Seller receives: $93.00 (93%)
└── Net platform profit: ~$3.60 (3.6%)
```

## Implementation Details

### Security Features
- ✅ **Server-side only**: Fee calculation happens in Cloud Functions
- ✅ **No client manipulation**: Mobile app cannot modify fees
- ✅ **Stripe integration**: Uses Stripe's `application_fee_amount` feature
- ✅ **Transparent**: Fee amount shown to users before payment

### Payment Flow
1. **User initiates purchase** → Total amount: $100
2. **Cloud Function calculates** → Platform fee: $5 (5%)
3. **Stripe processes payment** → Buyer charged: $100
4. **Automatic split** → Platform: $5, Seller: $95 (minus Stripe fees)

### Code Implementation
```typescript
export const createPaymentIntent = functions.https.onCall(async (data, context) => {
  const { listing_id, amount, currency } = data;
  
  // Calculate platform fee (configurable here)
  const platformFee = Math.round(amount * PLATFORM_FEE_RATE);
  const sellerAmount = amount - platformFee;
  
  // Create Stripe payment intent with platform fee
  const paymentIntent = await stripe.paymentIntents.create({
    amount,                           // Total charged to buyer
    currency,
    application_fee_amount: platformFee,  // Platform's cut
    transfer_data: {
      destination: sellerStripeAccountId, // Seller gets the rest
    },
    metadata: {
      platform_fee: platformFee.toString(),
      seller_amount: sellerAmount.toString(),
    },
  });
});
```

## Fee Display to Users

### In Listing Detail Screen
```dart
// Show fee breakdown before purchase
Column(
  children: [
    Text('Item Price: \$${listing.price.toStringAsFixed(2)}'),
    Text('Platform Fee (5%): \$${(listing.price * 0.05).toStringAsFixed(2)}'),
    Text('You Pay: \$${listing.price.toStringAsFixed(2)}'),
    Divider(),
    Text('Seller Receives: \$${(listing.price * 0.95).toStringAsFixed(2)}'),
  ],
)
```

### In Seller Dashboard
```dart
// Show what seller will receive
Text('You will receive: \$${(listingPrice * 0.95).toStringAsFixed(2)} (after 5% platform fee)')
```

## Compliance & Transparency

### Legal Requirements
- ✅ **Clear disclosure**: Fee percentage shown before purchase
- ✅ **No hidden fees**: Total amount matches what buyer pays
- ✅ **Seller awareness**: Sellers know fee structure upfront
- ✅ **Receipt details**: Platform fee itemized in transaction records

### Best Practices
- Always show fee percentage, not just dollar amount
- Display net seller amount during listing creation
- Include fee information in terms of service
- Provide clear receipts for all transactions

## Competitive Analysis

### Marketplace Fee Comparison
- **eBay**: 10-13% final value fee
- **Mercari**: 10% selling fee
- **Poshmark**: 20% commission
- **Facebook Marketplace**: 5% selling fee
- **SwapDotz**: 5% platform fee ✅ Competitive

## Configuration Changes

### To Change the Platform Fee:

1. **Update Cloud Functions**:
   ```bash
   cd firebase/functions/src
   # Edit payments.ts, change PLATFORM_FEE_RATE
   ```

2. **Update Documentation**:
   ```bash
   # Update all references to 5% in:
   # - PAYMENT_INTEGRATION_GUIDE.md
   # - MARKETPLACE_STATUS.md
   # - This file
   ```

3. **Update UI Text**:
   ```bash
   # Update any hardcoded "5%" references in:
   # - lib/screens/listing_detail_screen.dart
   # - lib/screens/create_listing_screen.dart
   ```

4. **Deploy Changes**:
   ```bash
   cd firebase
   firebase deploy --only functions
   ```

5. **Test Thoroughly**:
   - Create test listing
   - Make test purchase
   - Verify fee calculation
   - Check seller receives correct amount

---

**Current Status**: ✅ 5% platform fee correctly implemented and secure
**Last Updated**: January 2025
**Next Review**: When considering fee adjustments 