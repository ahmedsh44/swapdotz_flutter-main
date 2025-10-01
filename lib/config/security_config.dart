/// Centralized security configuration for SwapDotz anti-spoofing system
class SecurityConfig {
  // Trust score thresholds
  static const double minimumTrustScore = 0.8;
  static const double warningTrustScore = 0.9;
  static const double behaviorThreshold = 0.7;

  // Rate limiting settings
  static const int maxRequestsPerMinute = 10;
  static const int maxRequestsPerHour = 100;
  static const int maxRequestsPerDay = 500;
  
  // Timing thresholds (milliseconds)
  static const int minInteractionInterval = 1000; // 1 second
  static const int maxRequestAge = 300000; // 5 minutes
  static const int replayProtectionWindow = 30000; // 30 seconds
  
  // Challenge settings
  static const int challengeLength = 16;
  static const int challengeTimeoutMs = 30000; // 30 seconds
  static const int maxChallengeAttempts = 3;
  
  // Device fingerprint settings
  static const int maxDevicesPerUser = 5;
  static const int fingerprintRotationDays = 30;
  
  // Behavioral analysis settings
  static const int maxBehaviorHistorySize = 50;
  static const int minInteractionsForAnalysis = 5;
  static const double maxDeviationThreshold = 2.0;
  
  // Session security
  static const int sessionTimeoutMinutes = 30;
  static const int maxConcurrentSessions = 3;
  
  // IP reputation settings
  static const int maxViolationsPerIP = 5;
  static const int ipBlacklistDurationHours = 24;
  
  // Certificate pinning
  static const bool enableCertificatePinning = true;
  static const bool allowFallbackCertificates = false;
  
  // Biometric settings
  static const bool requireBiometricForHighValue = true;
  static const double highValueThreshold = 100.0; // USD
  static const bool allowFallbackAuthentication = false;
  
  // NFC security settings
  static const int maxNFCRetries = 3;
  static const int nfcTimeoutSeconds = 30;
  static const bool requirePhysicalPresence = true;
  static const int physicalPresenceChecks = 3;
  
  // GPS anti-spoofing settings
  static const bool enableGPSValidation = true;
  static const double maxAllowableSpeed = 200.0; // m/s (720 km/h)
  static const double maxInstantTeleport = 10000.0; // 10km instant movement
  static const double minGPSAccuracy = 100.0; // meters
  static const int maxLocationHistory = 20;
  static const bool allowIndoorOperations = true;
  static const bool allowNoLocationOperations = true;
  static const double indoorMinTrustScore = 0.6;
  static const double noLocationMinTrustScore = 0.5;
  
  // Logging and monitoring
  static const bool enableSecurityLogging = true;
  static const bool enableRealTimeAlerts = true;
  static const int maxLogRetentionDays = 90;
  
  // Development/debug settings
  static const bool isDebugMode = false; // Set to false in production
  static const bool allowTestFunctions = false; // Set to false in production
  static const bool bypassSecurityInDebug = false; // NEVER set to true in production
  
  /// Get security level based on operation type
  static SecurityLevel getSecurityLevel(String operationType) {
    switch (operationType) {
      case 'token_transfer':
      case 'ownership_change':
      case 'marketplace_transaction':
        return SecurityLevel.critical;
      
      case 'seller_verification':
      case 'buyer_verification':
      case 'payment_processing':
        return SecurityLevel.high;
      
      case 'high_value_transaction':
      case 'admin_operation':
        return SecurityLevel.critical;
      
      case 'token_read':
      case 'metadata_update':
      case 'profile_update':
        return SecurityLevel.medium;
      
      case 'public_read':
      case 'search':
      case 'browse':
        return SecurityLevel.low;
      
      default:
        return SecurityLevel.medium;
    }
  }
  
  /// Get required trust score for operation
  static double getRequiredTrustScore(SecurityLevel level) {
    switch (level) {
      case SecurityLevel.critical:
        return 0.95;
      case SecurityLevel.high:
        return 0.85;
      case SecurityLevel.medium:
        return 0.75;
      case SecurityLevel.low:
        return 0.60;
    }
  }
  
  /// Check if biometric authentication is required
  static bool requiresBiometric(SecurityLevel level, {double? value}) {
    if (level == SecurityLevel.critical) return true;
    if (level == SecurityLevel.high && requireBiometricForHighValue) {
      return value != null && value >= highValueThreshold;
    }
    return false;
  }
  
  /// Get rate limit for operation type
  static int getRateLimit(String operationType) {
    switch (operationType) {
      case 'token_transfer':
      case 'ownership_change':
        return 5; // Very restrictive for critical operations
      
      case 'seller_verification':
      case 'buyer_verification':
        return 10;
      
      case 'token_read':
      case 'metadata_update':
        return 30;
      
      case 'public_read':
      case 'search':
        return 100;
      
      default:
        return maxRequestsPerMinute;
    }
  }
  
  /// Validate security configuration
  static bool validateConfiguration() {
    final errors = <String>[];
    
    // Check critical security settings
    if (minimumTrustScore < 0.5) {
      errors.add('Minimum trust score too low: $minimumTrustScore');
    }
    
    if (bypassSecurityInDebug && !isDebugMode) {
      errors.add('Security bypass enabled outside debug mode');
    }
    
    if (allowTestFunctions && !isDebugMode) {
      errors.add('Test functions enabled outside debug mode');
    }
    
    if (minInteractionInterval < 500) {
      errors.add('Minimum interaction interval too low: $minInteractionInterval');
    }
    
    if (maxRequestAge > 600000) { // 10 minutes
      errors.add('Maximum request age too high: $maxRequestAge');
    }
    
    if (errors.isNotEmpty) {
      print('🚨 SECURITY CONFIGURATION ERRORS:');
      for (final error in errors) {
        print('   - $error');
      }
      return false;
    }
    
    return true;
  }
  
  /// Get environment-specific configuration
  static Map<String, dynamic> getEnvironmentConfig(String environment) {
    switch (environment.toLowerCase()) {
      case 'production':
        return {
          'debug_mode': false,
          'test_functions': false,
          'security_bypass': false,
          'log_level': 'error',
          'min_trust_score': 0.9,
          'require_biometric': true,
          'certificate_pinning': true,
          'gps_validation': true,
          'allow_indoor': true,
          'allow_no_location': false,
        };
      
      case 'staging':
        return {
          'debug_mode': false,
          'test_functions': false,
          'security_bypass': false,
          'log_level': 'warn',
          'min_trust_score': 0.8,
          'require_biometric': true,
          'certificate_pinning': true,
          'gps_validation': true,
          'allow_indoor': true,
          'allow_no_location': true,
        };
      
      case 'development':
        return {
          'debug_mode': true,
          'test_functions': true,
          'security_bypass': false, // Still maintain security in dev
          'log_level': 'debug',
          'min_trust_score': 0.7,
          'require_biometric': false,
          'certificate_pinning': false,
          'gps_validation': true,
          'allow_indoor': true,
          'allow_no_location': true,
        };
      
      default:
        throw ArgumentError('Unknown environment: $environment');
    }
  }
}

/// Security levels for different operations
enum SecurityLevel {
  low,
  medium,
  high,
  critical,
}

/// Security policy definitions
class SecurityPolicy {
  final SecurityLevel level;
  final double requiredTrustScore;
  final bool requiresBiometric;
  final int maxRetries;
  final int timeoutSeconds;
  final List<String> requiredValidations;
  
  const SecurityPolicy({
    required this.level,
    required this.requiredTrustScore,
    required this.requiresBiometric,
    required this.maxRetries,
    required this.timeoutSeconds,
    required this.requiredValidations,
  });
  
  static const Map<String, SecurityPolicy> policies = {
    'token_transfer': SecurityPolicy(
      level: SecurityLevel.critical,
      requiredTrustScore: 0.95,
      requiresBiometric: true,
      maxRetries: 2,
      timeoutSeconds: 60,
      requiredValidations: [
        'device_fingerprint',
        'biometric_auth',
        'behavior_analysis',
        'nfc_challenge',
        'replay_protection',
        'rate_limiting',
      ],
    ),
    
    'seller_verification': SecurityPolicy(
      level: SecurityLevel.high,
      requiredTrustScore: 0.85,
      requiresBiometric: true,
      maxRetries: 3,
      timeoutSeconds: 45,
      requiredValidations: [
        'device_fingerprint',
        'biometric_auth',
        'behavior_analysis',
        'nfc_challenge',
        'replay_protection',
      ],
    ),
    
    'token_read': SecurityPolicy(
      level: SecurityLevel.medium,
      requiredTrustScore: 0.75,
      requiresBiometric: false,
      maxRetries: 3,
      timeoutSeconds: 30,
      requiredValidations: [
        'device_fingerprint',
        'behavior_analysis',
        'replay_protection',
      ],
    ),
    
    'public_browse': SecurityPolicy(
      level: SecurityLevel.low,
      requiredTrustScore: 0.60,
      requiresBiometric: false,
      maxRetries: 5,
      timeoutSeconds: 15,
      requiredValidations: [
        'rate_limiting',
      ],
    ),
  };
  
  /// Get security policy for operation
  static SecurityPolicy? getPolicy(String operationType) {
    return policies[operationType];
  }
} 