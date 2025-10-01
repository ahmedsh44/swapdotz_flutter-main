/// Stripe Configuration for SwapDotz Marketplace
/// 
/// IMPORTANT: Set isProduction to true and add your live keys for production
/// Get your live keys from: https://dashboard.stripe.com/apikeys
class StripeConfig {
  // Set this to true for production
  static const bool isProduction = false; // TODO: Set to true for production
  
  // Test keys for development
  static const String testPublishableKey = 'pk_test_51S029YEEko14MgJMCs14Fu2R4iccxqlWZ4VZesFlRiuJD9NTNhB4O7ec37odXRBHzj9G2HGA9AnSAQeXtkLWjvrw00nCcTfpxQ';
  
  // Live keys for production (replace with your actual live keys)
  static const String livePublishableKey = 'pk_live_YOUR_LIVE_PUBLISHABLE_KEY'; // TODO: Replace with your live key
  
  // Active key based on environment
  static String get publishableKey => isProduction ? livePublishableKey : testPublishableKey;
  
  // Merchant configuration
  static const String merchantDisplayName = 'SwapDotz Marketplace';
  static const String merchantCountryCode = 'US';
  
  // Platform fee configuration
  static const double platformFeeRate = 0.05; // 5% platform fee
  
  // Currency settings
  static const String defaultCurrency = 'usd';
  
  // Connect settings for onboarding sellers
  static const String connectAccountType = 'express'; // Express accounts for simplified onboarding
  
  // Charge model
  static const String chargeType = 'destination'; // Using destination charges (platform processes payments)
  
  // Return URLs for Connect onboarding
  static const String connectReturnUrl = 'https://swapdotz.com/connect/return';
  static const String connectRefreshUrl = 'https://swapdotz.com/connect/refresh';
} 