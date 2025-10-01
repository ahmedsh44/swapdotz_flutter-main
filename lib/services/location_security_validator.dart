import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'gps_anti_spoofing_service.dart';
import '../config/security_config.dart';

/// Unified location security validator with indoor/no-GPS support
class LocationSecurityValidator {
  static const Map<String, LocationPolicy> _operationPolicies = {
    // Operations that WRITE GPS location to SwapDot - Maximum anti-spoofing required
    'write_location_to_swapdot': LocationPolicy(
      requireGPS: true, // Must have GPS when writing location
      maxSpoofingTolerance: 0.0, // Zero tolerance for spoofing
      requireHighAccuracy: true,
      maxTrustScoreDegrade: 0.0,
      blockEmulator: true,
      blockVPN: true,
      blockMockGPS: true,
    ),
    
    'update_travel_location': LocationPolicy(
      requireGPS: true, // GPS required for travel tracking
      maxSpoofingTolerance: 0.0, // Zero tolerance
      requireHighAccuracy: true,
      maxTrustScoreDegrade: 0.0,
      blockEmulator: true,
      blockVPN: true,
      blockMockGPS: true,
    ),
    
    // Operations that DON'T write location - No GPS protection needed
    'token_transfer': LocationPolicy(
      requireGPS: false, // No GPS needed - just transferring ownership
      maxSpoofingTolerance: 1.0, // No spoofing protection needed
      requireHighAccuracy: false,
      maxTrustScoreDegrade: 1.0,
      blockEmulator: false,
      blockVPN: false,
      blockMockGPS: false,
    ),
    
    'seller_verification': LocationPolicy(
      requireGPS: false, // No GPS needed - just proving ownership
      maxSpoofingTolerance: 1.0, // No spoofing protection needed
      requireHighAccuracy: false,
      maxTrustScoreDegrade: 1.0,
      blockEmulator: false,
      blockVPN: false,
      blockMockGPS: false,
    ),
    
    'marketplace_browse': LocationPolicy(
      requireGPS: false, // No GPS needed for browsing
      maxSpoofingTolerance: 1.0, // No spoofing protection needed
      requireHighAccuracy: false,
      maxTrustScoreDegrade: 1.0,
      blockEmulator: false,
      blockVPN: false,
      blockMockGPS: false,
    ),
    
    'marketplace_purchase': LocationPolicy(
      requireGPS: false, // No GPS needed for purchases
      maxSpoofingTolerance: 1.0, // No spoofing protection needed
      requireHighAccuracy: false,
      maxTrustScoreDegrade: 1.0,
      blockEmulator: false,
      blockVPN: false,
      blockMockGPS: false,
    ),
    
    'admin_operation': LocationPolicy(
      requireGPS: false, // Admin operations don't need GPS unless writing location
      maxSpoofingTolerance: 1.0,
      requireHighAccuracy: false,
      maxTrustScoreDegrade: 1.0,
      blockEmulator: false,
      blockVPN: false,
      blockMockGPS: false,
    ),
  };

  /// Validate location security for a specific operation
  static Future<LocationSecurityResult> validateLocationSecurity({
    required String operationType,
    double? transactionValue,
    Map<String, dynamic>? additionalContext,
  }) async {
    print('📍 LOCATION SECURITY: Validating for operation: $operationType');
    
    final policy = _getLocationPolicy(operationType, transactionValue);
    final result = LocationSecurityResult();
    
    try {
      // Step 1: Initialize GPS anti-spoofing
      await GPSAntiSpoofingService.initialize();
      
      // Step 2: Validate GPS with operation-specific requirements
      final gpsValidation = await GPSAntiSpoofingService.validateLocation(
        allowIndoorFallback: !policy.requireGPS,
        requireHighAccuracy: policy.requireHighAccuracy,
        operationType: operationType,
      );
      
      // Step 3: Apply operation-specific validation
      await _applyOperationSpecificValidation(
        gpsValidation,
        policy,
        result,
        operationType,
        transactionValue,
      );
      
      // Step 4: Calculate final security score
      _calculateLocationSecurityScore(gpsValidation, policy, result);
      
      // Step 5: Determine if operation should be allowed
      _determineOperationAllowance(result, policy, operationType);
      
      // Step 6: Log security decision
      await _logLocationSecurityDecision(result, operationType, transactionValue);
      
      return result;
      
    } catch (e) {
      print('🚨 LOCATION SECURITY ERROR: $e');
      result.addError('Location security validation failed: $e');
      result.allowOperation = false;
      return result;
    }
  }

  /// Get location policy for operation type
  static LocationPolicy _getLocationPolicy(String operationType, double? value) {
    // Check for high-value override
    if (value != null && value >= SecurityConfig.highValueThreshold) {
      return _operationPolicies['high_value_transaction']!;
    }
    
    return _operationPolicies[operationType] ?? _operationPolicies['public_browse']!;
  }

  /// Apply operation-specific validation rules
  static Future<void> _applyOperationSpecificValidation(
    GPSValidationResult gpsValidation,
    LocationPolicy policy,
    LocationSecurityResult result,
    String operationType,
    double? transactionValue,
  ) async {
    
    // Check GPS requirement vs availability
    if (policy.requireGPS && (gpsValidation.indoorMode || gpsValidation.noLocationMode)) {
      result.addError('GPS required for $operationType but not available');
      return;
    }
    
    // For location-writing operations, apply strict blocking rules
    if (operationType == 'write_location_to_swapdot' || operationType == 'update_travel_location') {
      // Block emulators
      if (policy.blockEmulator && gpsValidation.spoofingIndicators.contains('emulator_detected')) {
        result.addError('Location writing blocked: Emulator detected');
        return;
      }
      
      if (policy.blockEmulator && gpsValidation.spoofingIndicators.contains('ios_simulator_detected')) {
        result.addError('Location writing blocked: iOS Simulator detected');
        return;
      }
      
      // Block VPN usage
      if (policy.blockVPN && gpsValidation.spoofingIndicators.contains('high_network_latency')) {
        result.addError('Location writing blocked: VPN or high latency network detected');
        return;
      }
      
      // Block mock GPS
      if (policy.blockMockGPS && gpsValidation.spoofingIndicators.contains('mock_location_enabled')) {
        result.addError('Location writing blocked: Mock GPS detected');
        return;
      }
      
      // Block any other spoofing indicators for location writing
      if (gpsValidation.spoofingIndicators.isNotEmpty) {
        result.addError('Location writing blocked: GPS spoofing detected (${gpsValidation.spoofingIndicators.join(', ')})');
        return;
      }
    }
    
    // Check spoofing tolerance for other operations
    final spoofingScore = gpsValidation.spoofingIndicators.length / 10.0; // Normalize
    if (spoofingScore > policy.maxSpoofingTolerance) {
      result.addError('Spoofing indicators exceed tolerance for $operationType');
      result.addInfo('Spoofing score: ${spoofingScore.toStringAsFixed(2)}, tolerance: ${policy.maxSpoofingTolerance}');
    }
    
    // Check accuracy requirements
    if (policy.requireHighAccuracy && gpsValidation.trustScore < 0.9) {
      result.addWarning('High accuracy required but GPS quality insufficient');
    }
    
    // Operation-specific checks
    switch (operationType) {
      case 'token_transfer':
        await _validateTokenTransferLocation(gpsValidation, result);
        break;
        
      case 'marketplace_transaction':
        await _validateMarketplaceLocation(gpsValidation, result, transactionValue);
        break;
        
      case 'seller_verification':
        await _validateSellerLocation(gpsValidation, result);
        break;
        
      case 'admin_operation':
        await _validateAdminLocation(gpsValidation, result);
        break;
    }
  }

  /// Validate location for token transfers
  static Future<void> _validateTokenTransferLocation(
    GPSValidationResult gpsValidation,
    LocationSecurityResult result,
  ) async {
    // Token transfers can happen indoors, but check for obvious spoofing
    if (gpsValidation.spoofingIndicators.contains('instant_teleportation')) {
      result.addError('Token transfer blocked due to teleportation detection');
    }
    
    if (gpsValidation.spoofingIndicators.contains('impossible_speed')) {
      result.addWarning('Unusual movement speed detected during token transfer');
    }
    
    // Allow indoor transfers with warning
    if (gpsValidation.indoorMode) {
      result.addInfo('Token transfer in indoor mode - reduced location verification');
    }
    
    result.addValidation('token_transfer_location', true);
  }

  /// Validate location for marketplace transactions
  static Future<void> _validateMarketplaceLocation(
    GPSValidationResult gpsValidation,
    LocationSecurityResult result,
    double? value,
  ) async {
    // Higher scrutiny for high-value transactions
    if (value != null && value >= SecurityConfig.highValueThreshold) {
      if (gpsValidation.noLocationMode) {
        result.addError('High-value transaction requires location verification');
        return;
      }
      
      if (gpsValidation.spoofingIndicators.isNotEmpty) {
        result.addError('High-value transaction blocked due to location spoofing indicators');
        return;
      }
    }
    
    // Standard marketplace validation
    if (gpsValidation.spoofingIndicators.contains('mock_location_enabled')) {
      result.addWarning('Mock locations detected - marketplace purchase may be restricted');
    }
    
    result.addValidation('marketplace_location', true);
  }

  /// Validate location for seller verification
  static Future<void> _validateSellerLocation(
    GPSValidationResult gpsValidation,
    LocationSecurityResult result,
  ) async {
    // Sellers need to prove they have the physical token, but can be indoors
    if (gpsValidation.spoofingIndicators.contains('repeated_coordinates')) {
      result.addWarning('Repeated exact coordinates may indicate verification gaming');
    }
    
    if (gpsValidation.indoorMode) {
      result.addInfo('Seller verification in indoor mode - using alternative validation');
    }
    
    result.addValidation('seller_verification_location', true);
  }

  /// Validate location for admin operations
  static Future<void> _validateAdminLocation(
    GPSValidationResult gpsValidation,
    LocationSecurityResult result,
  ) async {
    // Admin operations require the highest location security
    if (gpsValidation.indoorMode || gpsValidation.noLocationMode) {
      result.addError('Admin operations require GPS location verification');
      return;
    }
    
    if (gpsValidation.spoofingIndicators.isNotEmpty) {
      result.addError('Admin operation blocked due to location spoofing indicators');
      return;
    }
    
    if (gpsValidation.trustScore < 0.9) {
      result.addError('Admin operation requires high GPS confidence (≥0.9)');
      return;
    }
    
    result.addValidation('admin_location', true);
  }

  /// Calculate final location security score
  static void _calculateLocationSecurityScore(
    GPSValidationResult gpsValidation,
    LocationPolicy policy,
    LocationSecurityResult result,
  ) {
    double score = gpsValidation.trustScore;
    
    // Apply policy-specific adjustments
    if (gpsValidation.indoorMode && !policy.requireGPS) {
      // Indoor mode is acceptable for this operation
      score = max(score, 0.7); // Minimum acceptable score for indoor
    }
    
    if (gpsValidation.noLocationMode && !policy.requireGPS) {
      // No location is acceptable for this operation
      score = max(score, 0.6); // Minimum acceptable score for no location
    }
    
    // Degrade score based on policy tolerance
    final maxDegradation = policy.maxTrustScoreDegrade;
    score = max(score, 1.0 - maxDegradation);
    
    result.locationSecurityScore = score;
  }

  /// Determine if operation should be allowed
  static void _determineOperationAllowance(
    LocationSecurityResult result,
    LocationPolicy policy,
    String operationType,
  ) {
    // Check for blocking errors
    if (result.errors.isNotEmpty) {
      result.allowOperation = false;
      result.blockingReason = 'Location security errors: ${result.errors.join(', ')}';
      return;
    }
    
    // Check minimum score requirement
    final requiredScore = _getRequiredScoreForOperation(operationType);
    if (result.locationSecurityScore < requiredScore) {
      result.allowOperation = false;
      result.blockingReason = 'Location security score ${result.locationSecurityScore.toStringAsFixed(2)} below required ${requiredScore.toStringAsFixed(2)}';
      return;
    }
    
    // Operation allowed
    result.allowOperation = true;
    
    // Add any conditions or warnings
    if (result.warnings.isNotEmpty) {
      result.operationConditions.addAll(result.warnings);
    }
  }

  /// Get required score for operation type
  static double _getRequiredScoreForOperation(String operationType) {
    switch (operationType) {
      case 'admin_operation':
        return 0.9;
      case 'high_value_transaction':
        return 0.85;
      case 'token_transfer':
      case 'seller_verification':
        return 0.7;
      case 'marketplace_transaction':
        return 0.6;
      default:
        return 0.5;
    }
  }

  /// Log location security decision
  static Future<void> _logLocationSecurityDecision(
    LocationSecurityResult result,
    String operationType,
    double? transactionValue,
  ) async {
    if (!result.allowOperation || result.locationSecurityScore < 0.8) {
      print('📍 LOCATION SECURITY DECISION:');
      print('   Operation: $operationType');
      print('   Allowed: ${result.allowOperation}');
      print('   Security Score: ${result.locationSecurityScore.toStringAsFixed(2)}');
      print('   Errors: ${result.errors.length}');
      print('   Warnings: ${result.warnings.length}');
      
      if (transactionValue != null) {
        print('   Transaction Value: \$${transactionValue.toStringAsFixed(2)}');
      }
      
      if (!result.allowOperation) {
        print('   Blocking Reason: ${result.blockingReason}');
      }
    }
  }

  /// Check if location validation is required for operation
  static bool isLocationValidationRequired(String operationType) {
    final policy = _operationPolicies[operationType];
    return policy?.requireGPS ?? false;
  }

  /// Get location requirements for UI display
  static Map<String, dynamic> getLocationRequirements(String operationType) {
    final policy = _operationPolicies[operationType] ?? _operationPolicies['public_browse']!;
    
    return {
      'requires_gps': policy.requireGPS,
      'requires_high_accuracy': policy.requireHighAccuracy,
      'indoor_allowed': !policy.requireGPS,
      'max_spoofing_tolerance': policy.maxSpoofingTolerance,
      'description': _getRequirementDescription(operationType, policy),
    };
  }

  /// Get human-readable requirement description
  static String _getRequirementDescription(String operationType, LocationPolicy policy) {
    if (policy.requireGPS) {
      return 'This operation requires GPS location verification for security.';
    } else if (policy.maxSpoofingTolerance > 0.3) {
      return 'This operation works without location services.';
    } else {
      return 'This operation works indoors but performs location verification when possible.';
    }
  }
}

/// Location policy for different operation types
class LocationPolicy {
  final bool requireGPS;
  final double maxSpoofingTolerance;
  final bool requireHighAccuracy;
  final double maxTrustScoreDegrade;
  final bool blockEmulator;
  final bool blockVPN;
  final bool blockMockGPS;

  const LocationPolicy({
    required this.requireGPS,
    required this.maxSpoofingTolerance,
    required this.requireHighAccuracy,
    required this.maxTrustScoreDegrade,
    this.blockEmulator = false,
    this.blockVPN = false,
    this.blockMockGPS = false,
  });
}

/// Location security validation result
class LocationSecurityResult {
  double locationSecurityScore = 1.0;
  bool allowOperation = true;
  String? blockingReason;
  
  final Map<String, bool> validations = {};
  final List<String> errors = [];
  final List<String> warnings = [];
  final List<String> info = [];
  final List<String> operationConditions = [];

  void addValidation(String key, bool isValid) {
    validations[key] = isValid;
  }

  void addError(String error) {
    errors.add(error);
  }

  void addWarning(String warning) {
    warnings.add(warning);
  }

  void addInfo(String information) {
    info.add(information);
  }

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isSecure => allowOperation && locationSecurityScore >= 0.7;

  @override
  String toString() {
    return 'LocationSecurityResult(score: $locationSecurityScore, '
           'allowed: $allowOperation, errors: ${errors.length}, '
           'warnings: ${warnings.length})';
  }
} 