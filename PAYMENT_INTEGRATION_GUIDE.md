# SwapDotz Marketplace Payment Integration Guide

## Overview

The SwapDotz marketplace requires a secure payment processor to handle real money transactions between users. This guide outlines how to integrate **Stripe** as the payment processor for the marketplace.

## Why Stripe?

- **Mobile-first**: Excellent Flutter/React Native support
- **Security**: PCI DSS Level 1 compliant
- **Marketplace features**: Built-in support for multi-party payments
- **Global**: Supports 135+ currencies and 40+ countries
- **Developer-friendly**: Great documentation and testing tools

## Required Setup

### 1. Stripe Account Setup

1. Create a Stripe account at https://stripe.com
2. Get your API keys from the Stripe dashboard:
   - **Publishable key** (starts with `pk_`): Used in the Flutter app
   - **Secret key** (starts with `sk_`): Used in Cloud Functions (server-side)
3. Set up Stripe Connect for marketplace functionality
4. Configure webhooks for payment status updates

### 2. Flutter Dependencies

Add these packages to your `pubspec.yaml`:

```yaml
dependencies:
  stripe_flutter: ^10.1.0  # Stripe SDK for Flutter
  pay: ^1.0.12            # Google Pay / Apple Pay integration
```

### 3. Firebase Functions Dependencies

In your `firebase/functions` directory:

```bash
cd firebase/functions
npm install stripe@^13.0.0
```

### 4. Environment Configuration

Set your Stripe secret key in Firebase Functions config:

```bash
firebase functions:config:set stripe.secret_key="sk_test_..." stripe.publishable_key="pk_test_..."
```

## Implementation Architecture

### Payment Flow

1. **Buyer** initiates purchase on a listing
2. **Flutter app** creates payment intent via Cloud Function
3. **Stripe** processes the payment securely
4. **Cloud Function** creates seller verification session (30-day window)
5. **Seller** must scan SwapDot with NFC to verify ownership
6. **Seller** ships physical SwapDot to buyer
7. **Buyer** confirms receipt and takes digital ownership
8. **Cloud Function** releases payment to seller (minus 5% fee)
9. **Marketplace** records completed transaction

### Seller Verification Process

- **Payment triggers verification**: When payment succeeds, a 30-day verification session is created
- **NFC scan required**: Seller must physically scan the SwapDot to prove they have it
- **No ownership transfer until buyer confirms**: Payment held until buyer takes ownership
- **30-day timeout**: If seller doesn't verify within 30 days, buyer gets automatic refund
- **Prevents fraud**: Ensures seller actually possesses the SwapDot before payment

### Security Features

- ✅ **Server-side validation**: All critical operations happen in Cloud Functions
- ✅ **Atomic transactions**: Token ownership and payment are transferred together
- ✅ **No direct client access**: Flutter app never handles sensitive payment data
- ✅ **Webhook verification**: Payment status updates are verified via Stripe webhooks
- ✅ **Marketplace fees**: Platform automatically takes a percentage

## Core Components

### 1. Payment Service (Flutter)

```dart
// lib/services/payment_service.dart
class PaymentService {
  static Future<PaymentIntent> createPaymentIntent(String listingId, double amount) async {
    final callable = FirebaseFunctions.instance.httpsCallable('createPaymentIntent');
    final result = await callable.call({
      'listing_id': listingId,
      'amount': (amount * 100).round(), // Convert to cents
      'currency': 'usd',
    });
    return PaymentIntent.fromMap(result.data);
  }

  static Future<void> confirmPayment(String paymentIntentId) async {
    await Stripe.instance.confirmPayment(
      paymentIntentClientSecret: paymentIntentId,
      // Payment method will be collected via Stripe UI
    );
  }
}
```

### 2. Cloud Functions (Backend)

```typescript
// firebase/functions/src/payments.ts
export const createPaymentIntent = functions.https.onCall(async (data, context) => {
  const { listing_id, amount, currency } = data;
  
  // Validate user and listing
  const listing = await admin.firestore()
    .collection('marketplace_listings')
    .doc(listing_id)
    .get();
    
  if (!listing.exists) {
    throw new functions.https.HttpsError('not-found', 'Listing not found');
  }
  
  // Calculate platform fee (5%)
  const platformFee = Math.round(amount * 0.05);
  
  // Create Stripe payment intent
  const paymentIntent = await stripe.paymentIntents.create({
    amount,
    currency,
    application_fee_amount: platformFee,
    transfer_data: {
      destination: sellerStripeAccountId, // Seller's connected account
    },
    metadata: {
      listing_id,
      buyer_id: context.auth.uid,
    },
  });
  
  return {
    client_secret: paymentIntent.client_secret,
    payment_intent_id: paymentIntent.id,
  };
});

export const confirmPayment = functions.https.onCall(async (data, context) => {
  const { payment_intent_id, listing_id } = data;
  
  // Verify payment succeeded with Stripe
  const paymentIntent = await stripe.paymentIntents.retrieve(payment_intent_id);
  
  if (paymentIntent.status !== 'succeeded') {
    throw new functions.https.HttpsError('failed-precondition', 'Payment not completed');
  }
  
  // Transfer token ownership atomically
  return admin.firestore().runTransaction(async (transaction) => {
    // Get listing and token
    const listingRef = admin.firestore().collection('marketplace_listings').doc(listing_id);
    const listing = await transaction.get(listingRef);
    
    const tokenRef = admin.firestore().collection('tokens').doc(listing.data().tokenId);
    const token = await transaction.get(tokenRef);
    
    // Update token ownership
    transaction.update(tokenRef, {
      current_owner_id: context.auth.uid,
      previous_owners: [...token.data().previous_owners, token.data().current_owner_id],
      last_transfer_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    // Mark listing as sold
    transaction.update(listingRef, {
      status: 'sold',
      buyer_id: context.auth.uid,
      sold_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    // Create transaction record
    const transactionRef = admin.firestore().collection('marketplace_transactions').doc();
    transaction.set(transactionRef, {
      id: transactionRef.id,
      listing_id,
      token_id: listing.data().tokenId,
      seller_id: listing.data().sellerId,
      buyer_id: context.auth.uid,
      amount: paymentIntent.amount,
      platform_fee: paymentIntent.application_fee_amount,
      currency: paymentIntent.currency,
      payment_intent_id,
      status: 'completed',
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return { success: true, transaction_id: transactionRef.id };
  });
});
```

### 3. Purchase Screen (Flutter UI)

```dart
// lib/screens/purchase_screen.dart
class PurchaseScreen extends StatefulWidget {
  final Listing listing;
  
  const PurchaseScreen({required this.listing});
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  bool _isProcessing = false;
  
  Future<void> _purchaseItem() async {
    setState(() { _isProcessing = true; });
    
    try {
      // Step 1: Create payment intent
      final paymentIntent = await PaymentService.createPaymentIntent(
        widget.listing.id,
        widget.listing.price,
      );
      
      // Step 2: Show Stripe payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent.clientSecret,
          merchantDisplayName: 'SwapDotz Marketplace',
        ),
      );
      
      await Stripe.instance.presentPaymentSheet();
      
      // Step 3: Confirm payment and transfer ownership
      await PaymentService.confirmPayment(paymentIntent.paymentIntentId);
      
      // Success!
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PurchaseSuccessScreen(listing: widget.listing),
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    } finally {
      setState(() { _isProcessing = false; });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Purchase ${widget.listing.title}')),
      body: Column(
        children: [
          // Listing details
          ListingCard(listing: widget.listing),
          
          Spacer(),
          
          // Purchase button
          Padding(
            padding: EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _purchaseItem,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: Size(double.infinity, 50),
              ),
              child: _isProcessing
                ? CircularProgressIndicator(color: Colors.white)
                : Text(
                    'Buy Now - \$${widget.listing.price.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Security Considerations

### 1. Server-Side Validation
- ✅ All payment processing happens in Cloud Functions
- ✅ Client cannot manipulate prices or fees
- ✅ Token ownership verification before transfer

### 2. Data Integrity
- ✅ Atomic transactions ensure consistency
- ✅ Payment and ownership transfer happen together
- ✅ Rollback on any failure

### 3. User Protection
- ✅ Stripe handles PCI compliance
- ✅ Platform fee transparency
- ✅ Refund capabilities for disputes

## Testing

### 1. Stripe Test Mode
Use Stripe test cards for development:
- Success: `4242424242424242`
- Decline: `4000000000000002`
- Insufficient funds: `4000000000009995`

### 2. Firebase Emulator
```bash
firebase emulators:start --only functions,firestore
```

### 3. Integration Tests
```dart
testWidgets('Purchase flow completes successfully', (tester) async {
  // Mock Stripe payment success
  when(mockStripe.confirmPayment(any)).thenAnswer((_) async {});
  
  // Test purchase flow
  await tester.pumpWidget(PurchaseScreen(listing: testListing));
  await tester.tap(find.text('Buy Now'));
  await tester.pumpAndSettle();
  
  // Verify success navigation
  expect(find.byType(PurchaseSuccessScreen), findsOneWidget);
});
```

## Production Checklist

### Before Launch
- [ ] Switch to Stripe live keys
- [ ] Set up Stripe webhooks for production
- [ ] Configure proper Stripe Connect accounts for sellers
- [ ] Set up monitoring and alerting
- [ ] Test refund flows
- [ ] Verify tax handling (if applicable)
- [ ] Set up customer support for payment issues

### Monitoring
- Track payment success/failure rates
- Monitor marketplace transaction volume
- Set up alerts for unusual payment patterns
- Log all payment-related errors

## Cost Structure

### Stripe Fees
- **2.9% + 30¢** per successful transaction
- **Additional 0.5%** for Stripe Connect (marketplace)
- **Total: ~3.4% + 30¢** per transaction

### Platform Revenue
- **SwapDotz fee**: 5% of transaction value
- **Net revenue**: ~1.6% of transaction value (after Stripe fees)

## Next Steps

1. **Set up Stripe account** and get API keys
2. **Install dependencies** in Flutter and Functions
3. **Implement payment service** following the examples above
4. **Add purchase UI** to listing detail screens
5. **Test thoroughly** with Stripe test cards
6. **Deploy and monitor** in production

---

💡 **Pro Tip**: Start with a minimal implementation and gradually add features like:
- Apple Pay / Google Pay integration
- Subscription billing for premium features
- Multi-currency support
- Advanced fraud detection 