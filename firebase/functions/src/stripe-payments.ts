import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import Stripe from 'stripe';

// Initialize Stripe with your secret key
// IMPORTANT: Set this in Firebase config:
// firebase functions:config:set stripe.secret_key="sk_test_..."
const stripeKey = functions.config().stripe?.secret_key ||
  'sk_test_51S029YEEko14MgJMPjwoIWAckvKj6FeFdKOeZoMbKsJoZqsSVemjpkGFbr0lYAZd1tpLewQZEfZq9qZY1I0Da68x00JG6lu55W';
const stripe = new Stripe(stripeKey, {
  apiVersion: '2025-07-30.basil',
});

const db = admin.firestore();

// Platform fee rate (5%)
const PLATFORM_FEE_RATE = 0.05;

/**
 * Create a Checkout Session for marketplace transaction with shipping collection
 */
export const createCheckoutSession =
  functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated to make payments');
    }

    const { listing_id, amount, currency = 'usd', offer_id, requires_shipping, success_url, cancel_url } = data;

    try {
      // Get listing details
      let listingDoc = await db.collection('marketplace_listings').doc(listing_id).get();
      if (!listingDoc.exists) {
        listingDoc = await db.collection('listings').doc(listing_id).get();
        if (!listingDoc.exists) {
          throw new functions.https.HttpsError('not-found', 'Listing not found');
        }
      }

      const listing = listingDoc.data()!;
      const sellerId = listing.sellerId || listing.seller_id;

      // Create Stripe Checkout Session
      const session = await stripe.checkout.sessions.create({
        payment_method_types: ['card'],
        mode: 'payment',
        line_items: [
          {
            price_data: {
              currency: currency,
              product_data: {
                name: listing.title,
                description: listing.description,
                images: listing.images && listing.images.length > 0 ? [listing.images[0]] : [],
              },
              unit_amount: Math.round(amount * 100), // Convert to cents
            },
            quantity: 1,
          },
        ],
        // Collect shipping address if required
        shipping_address_collection: requires_shipping ? {
          allowed_countries: ['US', 'CA', 'GB', 'AU', 'NZ', 'FR', 'DE', 'IT', 'ES', 'NL', 'BE', 'CH', 'AT', 'SE', 'NO', 'DK', 'FI'],
        } : undefined,
        billing_address_collection: 'required',
        customer_email: context.auth.token?.email,
        metadata: {
          listing_id,
          offer_id: offer_id || '',
          buyer_id: context.auth.uid,
          seller_id: sellerId,
          token_id: listing.tokenId || listing.token_id || '',
        },
        success_url: success_url || 'https://swapdotz.web.app/payment/success',
        cancel_url: cancel_url || 'https://swapdotz.web.app/payment/cancel',
      });

      return {
        sessionId: session.id,
        url: session.url,
      };
    } catch (error: any) {
      console.error('Error creating checkout session:', error);
      throw new functions.https.HttpsError('internal', 'Failed to create checkout session');
    }
  });

/**
 * Create a payment intent for marketplace transaction using destination charges
 * (Keeping this for backwards compatibility)
 */
export const createPaymentIntent =
  functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated to make payments');
    }

    const { listing_id, amount, currency = 'usd', offer_id } = data;

    try {
    // Validate input
      if (!listing_id || !amount || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid payment parameters');
      }

          // Get listing details - try both collections for compatibility
    let listingDoc = await db.collection('marketplace_listings').doc(listing_id).get();
    if (!listingDoc.exists) {
      // Fallback to 'listings' collection
      listingDoc = await db.collection('listings').doc(listing_id).get();
      if (!listingDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Listing not found');
      }
    }

          const listing = listingDoc.data()!;
    
    // Get seller ID - handle both field names
    const sellerId = listing.sellerId || listing.seller_id;

    // Verify the buyer is not the seller
    if (sellerId === context.auth.uid) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Cannot purchase your own listing',
      );
    }

          // Get seller's Stripe account ID
      const sellerDoc = await db.collection('users').doc(sellerId).get();
      if (!sellerDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Seller not found');
      }

      const sellerData = sellerDoc.data()!;
      const sellerStripeAccountId = sellerData.stripe_account_id;

      // Calculate platform fee and transfer amount
      const platformFee = Math.round(amount * PLATFORM_FEE_RATE);
      const transferAmount = amount - platformFee;

      // Get or create Stripe customer for buyer
      const customerId = await getOrCreateStripeCustomer(context.auth.uid, context.auth.token?.email);

      // Create payment intent
      // NOTE: For testing, we're not using real Stripe Connect accounts
      // In production, uncomment the transfer_data section
      const paymentIntent = await stripe.paymentIntents.create({
        amount: amount, // Amount in cents
        currency: currency,
        customer: customerId,
        // COMMENTED OUT FOR TESTING - no real Stripe Connect accounts
        // transfer_data: {
        //   amount: transferAmount, // Amount to transfer to seller (minus platform fee)
        //   destination: sellerStripeAccountId, // Seller's connected account
        // },
        metadata: {
                listing_id,
      offer_id: offer_id || '',
      buyer_id: context.auth.uid,
      seller_id: sellerId,
      platform_fee: platformFee.toString(),
      transfer_amount: transferAmount.toString(), // Store for reference
      seller_stripe_account: sellerStripeAccountId || 'test_account', // Store for reference
      token_id: listing.tokenId || listing.token_id || '',
        },
        description: `Purchase of SwapDot: ${listing.title}`,
      });

      // Create ephemeral key for customer (for mobile SDK)
      const ephemeralKey = await stripe.ephemeralKeys.create(
        { customer: customerId },
        { apiVersion: '2025-07-30.basil' },
      );

      // Store payment intent in database for tracking
      await db.collection('payment_intents').doc(paymentIntent.id).set({
        payment_intent_id: paymentIntent.id,
              listing_id,
      offer_id: offer_id || null,
      buyer_id: context.auth.uid,
      seller_id: sellerId,
        amount,
        platform_fee: platformFee,
        transfer_amount: transferAmount,
        currency,
        status: 'pending',
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        clientSecret: paymentIntent.client_secret,
        ephemeralKey: ephemeralKey.secret,
        customerId: customerId,
        paymentIntentId: paymentIntent.id,
      };
    } catch (error: any) {
      console.error('Error creating payment intent:', error);
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError('internal', 'Failed to create payment intent');
    }
  });

/**
 * Create or get existing Stripe customer
 */
async function getOrCreateStripeCustomer(userId: string, email?: string): Promise<string> {
  // Check if user already has a Stripe customer ID
  const userDoc = await db.collection('users').doc(userId).get();
  const userData = userDoc.data();

  if (userData?.stripe_customer_id) {
    return userData.stripe_customer_id;
  }

  // Create new Stripe customer
  const customer = await stripe.customers.create({
    email: email,
    metadata: {
      firebase_uid: userId,
    },
  });

  // Save customer ID to user document
  await db.collection('users').doc(userId).update({
    stripe_customer_id: customer.id,
  });

  return customer.id;
}

/**
 * Create a connected account for a seller (Express account)
 */
export const createConnectedAccount = functions.https.onCall(async (data, context) => {
  // Verify user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const { email, country = 'US' } = data;

  try {
    // Check if user already has a Stripe account
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    const userData = userDoc.data();

    if (userData?.stripe_account_id) {
      // User already has an account, create new onboarding link
      const accountLink = await stripe.accountLinks.create({
        account: userData.stripe_account_id,
        refresh_url: 'https://swapdotz.com/connect/refresh',
        return_url: 'https://swapdotz.com/connect/return',
        type: 'account_onboarding',
      });

      return {
        accountId: userData.stripe_account_id,
        onboardingUrl: accountLink.url,
      };
    }

    // Create new Express account
    const account = await stripe.accounts.create({
      type: 'express',
      country: country,
      email: email || context.auth.token?.email,
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
      business_type: 'individual',
      metadata: {
        firebase_uid: context.auth.uid,
      },
    });

    // Save account ID to user document
    await db.collection('users').doc(context.auth.uid).update({
      stripe_account_id: account.id,
      stripe_onboarding_complete: false,
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
  } catch (error: any) {
    console.error('Error creating connected account:', error);
    throw new functions.https.HttpsError('internal', 'Failed to create connected account');
  }
});

/**
 * Webhook handler for Stripe events
 */
export const stripeWebhook = functions.https.onRequest(async (req, res) => {
  // Verify webhook signature
  const sig = req.headers['stripe-signature'] as string;
  const webhookSecret = functions.config().stripe?.webhook_secret;

  if (!webhookSecret) {
    console.error('Webhook secret not configured');
    res.status(400).send('Webhook secret not configured');
    return;
  }

  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err: any) {
    console.error('Webhook signature verification failed:', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  // Handle the event
  try {
    switch (event.type) {
    case 'payment_intent.succeeded':
      await handlePaymentSuccess(event.data.object as Stripe.PaymentIntent);
      break;

    case 'payment_intent.payment_failed':
      await handlePaymentFailure(event.data.object as Stripe.PaymentIntent);
      break;

    case 'account.updated':
      await handleAccountUpdate(event.data.object as Stripe.Account);
      break;

    case 'transfer.created':
      await handleTransferCreated(event.data.object as Stripe.Transfer);
      break;

    default:
      console.log(`Unhandled event type: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error: any) {
    console.error('Error processing webhook:', error);
    res.status(500).send('Webhook processing failed');
  }
});

/**
 * Handle Stripe webhook events
 * This processes successful payments and updates the marketplace accordingly
 */
export const handleStripeWebhook = functions.https.onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  
  // Get webhook secret from environment config
  // Set this with: firebase functions:config:set stripe.webhook_secret="whsec_..."
  const webhookSecret = functions.config().stripe?.webhook_secret;
  
  if (!webhookSecret) {
    console.error('Webhook secret not configured');
    res.status(400).send('Webhook secret not configured');
    return;
  }

  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
  } catch (err: any) {
    console.error('Webhook signature verification failed:', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  // Handle the event
  try {
    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentSuccess(event.data.object as Stripe.PaymentIntent);
        break;
      
      case 'checkout.session.completed':
        await handleCheckoutSuccess(event.data.object as Stripe.Checkout.Session);
        break;
      
      default:
        console.log(`Unhandled event type ${event.type}`);
    }

    res.json({ received: true });
  } catch (error) {
    console.error('Error processing webhook:', error);
    res.status(500).send('Error processing webhook');
  }
});

/**
 * Process successful payment intent
 */
async function handlePaymentSuccess(paymentIntent: Stripe.PaymentIntent) {
  const { listing_id, buyer_id, seller_id, offer_id } = paymentIntent.metadata;
  
  if (!listing_id || !buyer_id || !seller_id) {
    console.error('Missing required metadata in payment intent');
    return;
  }

  const batch = db.batch();
  
  try {
    // 1. Update listing status to sold and add buyer info
    const listingRef = db.collection('marketplace_listings').doc(listing_id);
    batch.update(listingRef, {
      status: 'sold',
      buyerId: buyer_id,
      soldAt: admin.firestore.FieldValue.serverTimestamp(),
      paymentIntentId: paymentIntent.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Create transaction record
    const transactionRef = db.collection('marketplace_transactions').doc();
    batch.set(transactionRef, {
      transactionId: transactionRef.id,
      listingId: listing_id,
      buyerId: buyer_id,
      sellerId: seller_id,
      offerId: offer_id || null,
      amount: paymentIntent.amount / 100, // Convert from cents
      currency: paymentIntent.currency,
      paymentIntentId: paymentIntent.id,
      status: 'completed',
      buyerRated: false,
      sellerRated: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. If there was an accepted offer, update it
    if (offer_id) {
      const offerRef = db.collection('marketplace_offers').doc(offer_id);
      batch.update(offerRef, {
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // 4. Update other pending offers to withdrawn
    const pendingOffers = await db.collection('marketplace_offers')
      .where('listingId', '==', listing_id)
      .where('status', '==', 'pending')
      .get();
    
    pendingOffers.forEach(doc => {
      batch.update(doc.ref, {
        status: 'withdrawn',
        withdrawnReason: 'listing_sold',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    // 5. Create notification for seller
    const notificationRef = db.collection('notifications').doc();
    batch.set(notificationRef, {
      userId: seller_id,
      type: 'sale_completed',
      title: 'Item Sold!',
      message: 'Your listing has been sold. Ship it to the buyer!',
      listingId: listing_id,
      buyerId: buyer_id,
      transactionId: transactionRef.id,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
    console.log(`Successfully processed payment for listing ${listing_id}`);
  } catch (error) {
    console.error('Error updating database after payment:', error);
    throw error;
  }
}

/**
 * Process successful checkout session (for items with shipping)
 */
async function handleCheckoutSuccess(session: Stripe.Checkout.Session) {
  // Get the payment intent to access metadata
  const paymentIntent = await stripe.paymentIntents.retrieve(session.payment_intent as string);
  
  // Get shipping details from the session
  const shippingDetails = (session as any).shipping_details || (session as any).shipping || session.shipping_options;
  
  if (shippingDetails) {
    // Store shipping information for the seller
    const { listing_id, seller_id, buyer_id } = paymentIntent.metadata;
    
    await db.collection('shipping_info').doc(listing_id).set({
      listingId: listing_id,
      buyerId: buyer_id,
      sellerId: seller_id,
      name: shippingDetails.name || session.customer_details?.name,
      address: shippingDetails.address || session.customer_details?.address,
      phone: session.customer_details?.phone || null,
      email: session.customer_details?.email || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  
  // Process the payment success
  await handlePaymentSuccess(paymentIntent);
}

/**
 * Handle failed payment
 */
async function handlePaymentFailure(paymentIntent: Stripe.PaymentIntent) {
  // Update payment intent record
  await db.collection('payment_intents').doc(paymentIntent.id).update({
    status: 'failed',
    failed_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Update listing status back to active if it was reserved
  const { listing_id } = paymentIntent.metadata;
  if (listing_id) {
    await db.collection('listings').doc(listing_id).update({
      status: 'active',
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

/**
 * Handle Stripe account updates
 */
async function handleAccountUpdate(account: Stripe.Account) {
  const userId = account.metadata?.firebase_uid;
  if (!userId) return;

  // Update user's Stripe account status
  await db.collection('users').doc(userId).update({
    stripe_onboarding_complete: account.details_submitted,
    stripe_charges_enabled: account.charges_enabled,
    stripe_payouts_enabled: account.payouts_enabled,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Handle transfer creation
 */
async function handleTransferCreated(transfer: Stripe.Transfer) {
  // Log transfer for tracking
  await db.collection('transfers').add({
    transfer_id: transfer.id,
    amount: transfer.amount,
    currency: transfer.currency,
    destination: transfer.destination,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Refund a payment (admin function)
 */
export const refundPayment = functions.https.onCall(async (data) => {
  // Verify admin role (implement your admin check)
  // if (!isAdmin(context.auth?.uid)) {
  //   throw new functions.https.HttpsError('permission-denied', 'Admin access required');
  // }

  const { payment_intent_id, reason } = data;

  try {
    const refund = await stripe.refunds.create({
      payment_intent: payment_intent_id,
      reason: reason || 'requested_by_customer',
    });

    // Update payment intent record
    await db.collection('payment_intents').doc(payment_intent_id).update({
      status: 'refunded',
      refunded_at: admin.firestore.FieldValue.serverTimestamp(),
      refund_id: refund.id,
    });

    return {
      refundId: refund.id,
      status: refund.status,
    };
  } catch (error: any) {
    console.error('Error creating refund:', error);
    throw new functions.https.HttpsError('internal', 'Failed to create refund');
  }
});
