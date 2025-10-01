# Stripe Connect Setup Guide for SwapDotz

## Overview
This guide will help you set up Stripe Connect for your SwapDotz marketplace based on the [Stripe Connect integration guide](https://docs.stripe.com/connect/design-an-integration).

## Recommended Configuration

Based on available options for your Stripe account:

| Property | Setting | Why |
|----------|---------|-----|
| **Onboarding** | Hosted | Quick launch with lowest integration effort |
| **Dashboard Access** | Express Dashboard | Balance of features and control |
| **Charge Type** | **Destination Charges** | Platform processes payments and transfers to sellers |
| **Who Pays Fees** | **Your Platform** | Platform pays Stripe fees (can be passed to sellers) |
| **Negative Balance Liability** | **Platform** | You handle risk management |

## Important: Destination Charges Model

Since Direct Charges are not available, we'll use **Destination Charges**:
- Payment goes through your platform account first
- You automatically transfer funds to the seller (minus platform fee)
- Customer sees your platform name on their statement
- You have more control over the payment flow

## Step 1: Create Stripe Account

1. **Sign up for Stripe**
   - Go to https://stripe.com and create an account
   - Complete your platform profile

2. **Enable Stripe Connect**
   - Go to https://dashboard.stripe.com/connect/overview
   - Click "Get started with Connect"
   - Choose "Marketplace" as your platform type

## Step 2: Get Your API Keys

1. **Test Keys (for development)**
   - Go to https://dashboard.stripe.com/test/apikeys
   - Copy your **Publishable key** (starts with `pk_test_`)
   - Copy your **Secret key** (starts with `sk_test_`)

2. **Live Keys (for production)**
   - Go to https://dashboard.stripe.com/apikeys
   - Copy your **Publishable key** (starts with `pk_live_`)
   - Copy your **Secret key** (starts with `sk_live_`)

3. **Update Your Config**
   - Open `/lib/config/stripe_config.dart`
   - Replace the placeholder publishable key with your actual key

## Step 3: Configure Connect Settings

1. **Platform Settings**
   - Go to https://dashboard.stripe.com/settings/connect
   - Set your platform name: "SwapDotz"
   - Upload your logo
   - Set support email and phone

2. **Onboarding Settings**
   - Go to https://dashboard.stripe.com/settings/connect/express_dashboard
   - Configure Express Dashboard branding
   - Set up your privacy policy and terms of service URLs

3. **OAuth Settings (for production)**
   - Go to https://dashboard.stripe.com/settings/connect/oauth
   - Add redirect URIs:
     - `https://swapdotz.com/connect/return`
     - `https://swapdotz.com/connect/refresh`

## Step 4: Set Up Firebase Functions

1. **Install Stripe in Functions**
   ```bash
   cd firebase/functions
   npm install stripe
   ```

2. **Set Environment Variables**
   ```bash
   firebase functions:config:set \
     stripe.secret_key="sk_test_YOUR_SECRET_KEY" \
     stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET"
   ```

3. **Create Payment Intent Function (Destination Charges)**
   Create `firebase/functions/src/payments.ts`:
   ```typescript
   import * as functions from 'firebase-functions';
   import Stripe from 'stripe';

   const stripe = new Stripe(functions.config().stripe.secret_key, {
     apiVersion: '2023-10-16',
   });

   export const createPaymentIntent = functions.https.onCall(async (data, context) => {
     // Verify user is authenticated
     if (!context.auth) {
       throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
     }

     const { listing_id, amount, currency, seller_stripe_account_id } = data;
     
     // Calculate platform fee (5%)
     const platformFee = Math.round(amount * 0.05);
     const transferAmount = amount - platformFee;
     
     // Create destination charge payment intent
     const paymentIntent = await stripe.paymentIntents.create({
       amount: amount,
       currency: currency,
       // Destination charge - automatically transfer to seller minus platform fee
       transfer_data: {
         amount: transferAmount, // Amount to transfer to seller
         destination: seller_stripe_account_id, // Seller's connected account
       },
       metadata: {
         listing_id,
         buyer_id: context.auth.uid,
         platform_fee: platformFee,
       },
     });

     // Create ephemeral key for customer
     const ephemeralKey = await stripe.ephemeralKeys.create(
       { customer: 'CUSTOMER_ID' },
       { apiVersion: '2023-10-16' }
     );

     return {
       clientSecret: paymentIntent.client_secret,
       ephemeralKey: ephemeralKey.secret,
       customerId: 'CUSTOMER_ID',
     };
   });

   // Onboard a seller (create connected account)
   export const createConnectedAccount = functions.https.onCall(async (data, context) => {
     if (!context.auth) {
       throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
     }

     const account = await stripe.accounts.create({
       type: 'express',
       country: 'US',
       email: data.email,
       capabilities: {
         card_payments: { requested: true },
         transfers: { requested: true },
       },
       metadata: {
         firebase_uid: context.auth.uid,
       },
     });

     // Create account link for onboarding
     const accountLink = await stripe.accountLinks.create({
       account: account.id,
       refresh_url: 'https://swapdotz.com/connect/refresh',
       return_url: 'https://swapdotz.com/connect/return',
       type: 'account_onboarding',
     });

     return {
       accountId: account.id,
       onboardingUrl: accountLink.url,
     };
   });
   ```

## Step 5: Configure Webhooks

1. **Set Up Webhook Endpoint**
   - Go to https://dashboard.stripe.com/webhooks
   - Add endpoint: `https://your-domain.com/stripe/webhook`
   - Select events:
     - `payment_intent.succeeded`
     - `payment_intent.payment_failed`
     - `account.updated`
     - `account.application.authorized`
     - `transfer.created`
     - `transfer.failed`

2. **Get Webhook Secret**
   - Copy the signing secret (starts with `whsec_`)
   - Add to Firebase config

## Step 6: Android Configuration

1. **Update AndroidManifest.xml**
   Add to `/android/app/src/main/AndroidManifest.xml`:
   ```xml
   <application>
     <!-- Stripe configuration -->
     <meta-data
       android:name="com.stripe.sdk.API_KEY"
       android:value="pk_test_YOUR_PUBLISHABLE_KEY" />
   </application>
   ```

2. **Enable Internet Permission**
   ```xml
   <uses-permission android:name="android.permission.INTERNET" />
   ```

## Step 7: iOS Configuration

1. **Update Info.plist**
   Add to `/ios/Runner/Info.plist`:
   ```xml
   <key>StripePublishableKey</key>
   <string>pk_test_YOUR_PUBLISHABLE_KEY</string>
   ```

2. **Configure Apple Pay (Optional)**
   - Add Apple Pay capability in Xcode
   - Configure merchant identifier: `merchant.com.swapdotz`

## Step 8: Test Your Integration

1. **Test Cards**
   Use these test card numbers:
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`
   - Authentication Required: `4000 0025 0000 3155`

2. **Test Connect Onboarding**
   - Create a test connected account
   - Complete the Express onboarding flow
   - Verify account appears in Dashboard

3. **Test Payment Flow**
   - Create a test listing
   - Initiate purchase
   - Complete payment with test card
   - Verify payment appears in Dashboard
   - Verify transfer to seller account

## Step 9: Go Live Checklist

- [ ] Replace test API keys with live keys
- [ ] Update webhook endpoints for production
- [ ] Configure production OAuth redirect URIs
- [ ] Set up SSL certificates
- [ ] Enable PCI compliance mode
- [ ] Review and accept Stripe Connect terms
- [ ] Test with real payment methods
- [ ] Set up monitoring and alerts

## Security Best Practices

1. **Never expose secret keys** - Only use them in server-side code
2. **Validate amounts server-side** - Never trust client-side amounts
3. **Use webhooks for critical updates** - Don't rely solely on client callbacks
4. **Implement idempotency** - Prevent duplicate charges
5. **Log all transactions** - Keep audit trail

## Support Resources

- [Stripe Connect Docs](https://docs.stripe.com/connect)
- [Destination Charges Guide](https://docs.stripe.com/connect/destination-charges)
- [Flutter Stripe SDK](https://pub.dev/packages/flutter_stripe)
- [Stripe Dashboard](https://dashboard.stripe.com)
- [Stripe Support](https://support.stripe.com)

## Platform Fee Structure with Destination Charges

Current configuration: **5% platform fee**

With destination charges, the flow is:
1. Buyer pays: $100 to your platform
2. Platform receives: $100
3. Platform keeps: $5 (5% fee)
4. Platform transfers to seller: $95
5. Stripe fees: Deducted from platform (about $3.20 for $100 transaction)

Your net profit: $5 - $3.20 = $1.80 per $100 transaction

To change the fee, update:
1. `/lib/config/stripe_config.dart` - `platformFeeRate`
2. Firebase Functions - `transferAmount` calculation 