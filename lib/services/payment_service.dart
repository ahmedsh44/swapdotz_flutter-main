import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/stripe_config.dart';

class PaymentService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Create and launch a Stripe Checkout Session with shipping collection
  static Future<bool> launchCheckoutSession({
    required String listingId,
    required double amount,
    bool requiresShipping = false,
    String? successUrl,
    String? cancelUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to make payments');
      }

      // Use deep links for mobile app or fallback URLs
      // For production, you should set up proper deep linking or create actual pages
      final defaultSuccessUrl = 'swapdotz://payment-success?listing_id=$listingId';
      final defaultCancelUrl = 'swapdotz://payment-cancel?listing_id=$listingId';
      
      // Fallback to web URLs if deep links aren't set up yet
      // These could be simple static pages that say "Payment successful" or "Payment cancelled"
      final fallbackSuccessUrl = 'https://swapdotz.web.app/payment/success.html';
      final fallbackCancelUrl = 'https://swapdotz.web.app/payment/cancel.html';

      // Call cloud function to create checkout session
      final callable = _functions.httpsCallable('createCheckoutSession');
      final result = await callable.call({
        'listing_id': listingId,
        'amount': amount,
        'currency': StripeConfig.defaultCurrency.toLowerCase(),
        'requires_shipping': requiresShipping,
        'success_url': successUrl ?? fallbackSuccessUrl,
        'cancel_url': cancelUrl ?? fallbackCancelUrl,
      });

      // Get the checkout URL
      final checkoutUrl = result.data['url'] as String?;
      if (checkoutUrl == null) {
        throw Exception('Failed to get checkout URL');
      }

      // Launch the checkout URL in a web browser
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return true;
      } else {
        throw Exception('Could not launch checkout');
      }
    } catch (e) {
      print('Error launching checkout session: $e');
      throw e;
    }
  }

  /// Initialize payment sheet for a listing purchase
  static Future<void> initPaymentSheet({
    required String listingId,
    required double amount,
    required String sellerName,
    String? offerId,
    bool requiresShipping = false,
    double? shippingCost,
  }) async {
    try {
      // 1. Create payment intent on server
      final paymentIntent = await createPaymentIntent(
        listingId: listingId,
        amount: amount,
        currency: StripeConfig.defaultCurrency,
        offerId: offerId,
      );

      // 2. Initialize the payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          // Main params
          paymentIntentClientSecret: paymentIntent.clientSecret,
          merchantDisplayName: StripeConfig.merchantDisplayName,
          
          // Customer params
          customerId: paymentIntent.customerId,
          customerEphemeralKeySecret: paymentIntent.ephemeralKey,
          
          // Billing collection configuration
          billingDetailsCollectionConfiguration: BillingDetailsCollectionConfiguration(
            email: CollectionMode.automatic,
            phone: CollectionMode.automatic,
            address: requiresShipping ? AddressCollectionMode.full : AddressCollectionMode.automatic,
            name: CollectionMode.automatic,
          ),
          
          // Allow delayed payment methods for shipping scenarios
          allowsDelayedPaymentMethods: requiresShipping,
          
          // Extra options
          applePay: PaymentSheetApplePay(
            merchantCountryCode: StripeConfig.merchantCountryCode,
          ),
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: StripeConfig.merchantCountryCode,
            testEnv: true, // Set to false in production
          ),
          style: ThemeMode.system,
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Colors.blue,
            ),
            shapes: PaymentSheetShape(
              borderRadius: 12,
              borderWidth: 0.5,
            ),
          ),
        ),
      );
    } catch (e) {
      print('Error initializing payment sheet: $e');
      throw e;
    }
  }

  /// Present the payment sheet to the user
  static Future<void> presentPaymentSheet() async {
    try {
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      print('Payment cancelled or failed: ${e.error.localizedMessage}');
      throw e;
    }
  }

  /// Create a payment intent for a marketplace transaction
  static Future<PaymentIntentResult> createPaymentIntent({
    required String listingId,
    required double amount,
    required String currency,
    String? offerId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to make payments');
      }

      final callable = _functions.httpsCallable('createPaymentIntent');
      final result = await callable.call({
        'listing_id': listingId,
        'amount': (amount * 100).round(), // Convert to cents
        'currency': currency.toLowerCase(),
        'offer_id': offerId,
      });

      return PaymentIntentResult.fromMap(result.data);
    } catch (e) {
      print('Error creating payment intent: $e');
      throw e;
    }
  }

  /// Confirm payment and create seller verification session
  static Future<SellerVerificationSessionResult> confirmPayment({
    required String paymentIntentId,
    required String listingId,
    required String tokenId,
    required double amount,
    String? offerId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to confirm payments');
      }

      // Create seller verification session instead of immediate transfer
      final callable = _functions.httpsCallable('createSellerVerificationSession');
      final result = await callable.call({
        'token_id': tokenId,
        'listing_id': listingId,
        'payment_intent_id': paymentIntentId,
        'amount': (amount * 100).round(), // Convert to cents
        'buyer_id': user.uid,
      });

      return SellerVerificationSessionResult.fromMap(result.data);
    } catch (e) {
      print('Error confirming payment: $e');
      throw e;
    }
  }

  /// Get user's Stripe customer ID or create one
  static Future<String> getOrCreateCustomer() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      final callable = _functions.httpsCallable('getOrCreateStripeCustomer');
      final result = await callable.call({});

      return result.data['customer_id'];
    } catch (e) {
      print('Error getting/creating Stripe customer: $e');
      throw e;
    }
  }

  /// Get user's saved payment methods
  static Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final customerId = await getOrCreateCustomer();
      
      final callable = _functions.httpsCallable('getPaymentMethods');
      final result = await callable.call({
        'customer_id': customerId,
      });

      final methods = result.data['payment_methods'] as List;
      return methods.map((m) => PaymentMethod.fromMap(m)).toList();
    } catch (e) {
      print('Error getting payment methods: $e');
      return [];
    }
  }

  /// Add a new payment method
  static Future<PaymentMethod> addPaymentMethod({
    required String paymentMethodId,
  }) async {
    try {
      final customerId = await getOrCreateCustomer();
      
      final callable = _functions.httpsCallable('attachPaymentMethod');
      final result = await callable.call({
        'customer_id': customerId,
        'payment_method_id': paymentMethodId,
      });

      return PaymentMethod.fromMap(result.data);
    } catch (e) {
      print('Error adding payment method: $e');
      throw e;
    }
  }

  /// Process a refund
  static Future<RefundResult> processRefund({
    required String transactionId,
    required double amount,
    required String reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('processRefund');
      final result = await callable.call({
        'transaction_id': transactionId,
        'amount': (amount * 100).round(), // Convert to cents
        'reason': reason,
      });

      return RefundResult.fromMap(result.data);
    } catch (e) {
      print('Error processing refund: $e');
      throw e;
    }
  }

  /// Get transaction details
  static Future<PaymentTransaction> getTransaction(String transactionId) async {
    try {
      final callable = _functions.httpsCallable('getPaymentTransaction');
      final result = await callable.call({
        'transaction_id': transactionId,
      });

      return PaymentTransaction.fromMap(result.data);
    } catch (e) {
      print('Error getting transaction: $e');
      throw e;
    }
  }
}

// Data Models

class PaymentIntentResult {
  final String clientSecret;
  final String paymentIntentId;
  final double amount;
  final String currency;
  final String status;
  final String? customerId;
  final String? ephemeralKey;

  PaymentIntentResult({
    required this.clientSecret,
    required this.paymentIntentId,
    required this.amount,
    required this.currency,
    required this.status,
    this.customerId,
    this.ephemeralKey,
  });

  factory PaymentIntentResult.fromMap(Map<String, dynamic> map) {
    return PaymentIntentResult(
      clientSecret: map['clientSecret'] ?? map['client_secret'],
      paymentIntentId: map['paymentIntentId'] ?? map['payment_intent_id'],
      amount: map['amount'] != null ? (map['amount'] as num).toDouble() / 100 : 0.0, // Convert from cents
      currency: map['currency'] ?? 'usd',
      status: map['status'] ?? 'pending',
      customerId: map['customerId'],
      ephemeralKey: map['ephemeralKey'],
    );
  }
}

class TransactionResult {
  final String transactionId;
  final String status;
  final String tokenId;
  final String sellerId;
  final String buyerId;
  final double amount;
  final DateTime completedAt;

  TransactionResult({
    required this.transactionId,
    required this.status,
    required this.tokenId,
    required this.sellerId,
    required this.buyerId,
    required this.amount,
    required this.completedAt,
  });

  factory TransactionResult.fromMap(Map<String, dynamic> map) {
    return TransactionResult(
      transactionId: map['transaction_id'],
      status: map['status'],
      tokenId: map['token_id'],
      sellerId: map['seller_id'],
      buyerId: map['buyer_id'],
      amount: (map['amount'] as num).toDouble(),
      completedAt: DateTime.parse(map['completed_at']),
    );
  }
}

class PaymentMethod {
  final String id;
  final String type;
  final String last4;
  final String brand;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  PaymentMethod({
    required this.id,
    required this.type,
    required this.last4,
    required this.brand,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'],
      type: map['type'],
      last4: map['last4'],
      brand: map['brand'],
      expMonth: map['exp_month'],
      expYear: map['exp_year'],
      isDefault: map['is_default'] ?? false,
    );
  }

  String get displayName {
    return '$brand •••• $last4';
  }

  String get expiryText {
    return '${expMonth.toString().padLeft(2, '0')}/$expYear';
  }
}

class RefundResult {
  final String refundId;
  final String status;
  final double amount;
  final String reason;
  final DateTime processedAt;

  RefundResult({
    required this.refundId,
    required this.status,
    required this.amount,
    required this.reason,
    required this.processedAt,
  });

  factory RefundResult.fromMap(Map<String, dynamic> map) {
    return RefundResult(
      refundId: map['refund_id'],
      status: map['status'],
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'],
      processedAt: DateTime.parse(map['processed_at']),
    );
  }
}

class PaymentTransaction {
  final String id;
  final String paymentIntentId;
  final String listingId;
  final String tokenId;
  final String sellerId;
  final String buyerId;
  final double amount;
  final double platformFee;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final Map<String, dynamic>? metadata;

  PaymentTransaction({
    required this.id,
    required this.paymentIntentId,
    required this.listingId,
    required this.tokenId,
    required this.sellerId,
    required this.buyerId,
    required this.amount,
    required this.platformFee,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.metadata,
  });

  factory PaymentTransaction.fromMap(Map<String, dynamic> map) {
    return PaymentTransaction(
      id: map['id'],
      paymentIntentId: map['payment_intent_id'],
      listingId: map['listing_id'],
      tokenId: map['token_id'],
      sellerId: map['seller_id'],
      buyerId: map['buyer_id'],
      amount: (map['amount'] as num).toDouble(),
      platformFee: (map['platform_fee'] as num).toDouble(),
      currency: map['currency'],
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
      completedAt: map['completed_at'] != null 
          ? DateTime.parse(map['completed_at']) 
          : null,
      metadata: map['metadata'],
    );
  }

  double get sellerAmount => amount - platformFee;
}

class SellerVerificationSessionResult {
  final String sessionId;
  final String tokenId;
  final String sellerId;
  final String buyerId;
  final String listingId;
  final String paymentIntentId;
  final double amount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String status;

  SellerVerificationSessionResult({
    required this.sessionId,
    required this.tokenId,
    required this.sellerId,
    required this.buyerId,
    required this.listingId,
    required this.paymentIntentId,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
  });

  factory SellerVerificationSessionResult.fromMap(Map<String, dynamic> map) {
    return SellerVerificationSessionResult(
      sessionId: map['session_id'],
      tokenId: map['token_id'],
      sellerId: map['seller_id'],
      buyerId: map['buyer_id'],
      listingId: map['listing_id'],
      paymentIntentId: map['payment_intent_id'],
      amount: (map['amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at']),
      expiresAt: DateTime.parse(map['expires_at']),
      status: map['status'],
    );
  }
} 