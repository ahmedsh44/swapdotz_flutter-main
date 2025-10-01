import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gps_anti_spoofing_service.dart';
import 'location_security_validator.dart';

/// Comprehensive anti-spoofing protection service
class AntiSpoofingService {
  static const String _deviceFingerprintKey = 'device_fingerprint_v2';
  static const String _behaviorProfileKey = 'behavior_profile_v1';
  static const String _sessionIntegrityKey = 'session_integrity_v1';
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static String? _deviceFingerprint;
  static Map<String, dynamic>? _behaviorProfile;

  /// Initialize anti-spoofing protection
  static Future<void> initialize() async {
    await _generateDeviceFingerprint();
    await _loadBehaviorProfile();
    await _validateSessionIntegrity();
  }

  /// Generate unique device fingerprint for device binding
  static Future<void> _generateDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we already have a fingerprint
    final existingFingerprint = prefs.getString(_deviceFingerprintKey);
    if (existingFingerprint != null) {
      _deviceFingerprint = existingFingerprint;
      return;
    }

    // Generate new fingerprint based on device characteristics
    final fingerprintData = <String, dynamic>{};

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        fingerprintData.addAll({
          'platform': 'android',
          'model': androidInfo.model,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'display': androidInfo.display,
          'hardware': androidInfo.hardware,
          'manufacturer': androidInfo.manufacturer,
          'product': androidInfo.product,
          'supported32BitAbis': androidInfo.supported32BitAbis,
          'supported64BitAbis': androidInfo.supported64BitAbis,
          'systemFeatures': androidInfo.systemFeatures,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        fingerprintData.addAll({
          'platform': 'ios',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'localizedModel': iosInfo.localizedModel,
          'identifierForVendor': iosInfo.identifierForVendor,
          'isPhysicalDevice': iosInfo.isPhysicalDevice,
        });
      }

      // Add app-specific data
      final packageInfo = await PackageInfo.fromPlatform();
      fingerprintData.addAll({
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Generate cryptographic hash of the fingerprint
      final fingerprintJson = json.encode(fingerprintData);
      final fingerprintBytes = utf8.encode(fingerprintJson);
      final digest = sha256.convert(fingerprintBytes);
      
      _deviceFingerprint = base64.encode(digest.bytes);
      
      // Store fingerprint securely
      await prefs.setString(_deviceFingerprintKey, _deviceFingerprint!);
      
      print('🔐 SECURITY: Device fingerprint generated: ${_deviceFingerprint!.substring(0, 16)}...');
      
    } catch (e) {
      print('⚠️ SECURITY: Failed to generate device fingerprint: $e');
      _deviceFingerprint = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Load and analyze user behavior profile
  static Future<void> _loadBehaviorProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = prefs.getString(_behaviorProfileKey);
    
    if (profileJson != null) {
      _behaviorProfile = json.decode(profileJson);
    } else {
      _behaviorProfile = {
        'scan_patterns': <String, int>{},
        'session_durations': <int>[],
        'interaction_timings': <int>[],
        'error_frequencies': <String, int>{},
        'location_patterns': <String, int>{},
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'total_sessions': 0,
      };
    }
  }

  /// Save behavior profile updates
  static Future<void> _saveBehaviorProfile() async {
    if (_behaviorProfile == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_behaviorProfileKey, json.encode(_behaviorProfile!));
  }

  /// Validate session integrity and detect tampering
  static Future<void> _validateSessionIntegrity() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSession = prefs.getString(_sessionIntegrityKey);
    final currentSession = _generateSessionToken();
    
    if (lastSession != null) {
      // Analyze session consistency
      final isConsistent = _analyzeSessionConsistency(lastSession, currentSession);
      if (!isConsistent) {
        await _reportSuspiciousActivity('session_inconsistency', {
          'last_session': lastSession.substring(0, 16),
          'current_session': currentSession.substring(0, 16),
        });
      }
    }
    
    await prefs.setString(_sessionIntegrityKey, currentSession);
  }

  /// Generate session token for integrity checking
  static String _generateSessionToken() {
    final sessionData = {
      'device_fingerprint': _deviceFingerprint,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'platform': Platform.operatingSystem,
      'app_state': 'active',
    };
    
    final sessionJson = json.encode(sessionData);
    final sessionBytes = utf8.encode(sessionJson);
    final digest = sha256.convert(sessionBytes);
    
    return base64.encode(digest.bytes);
  }

  /// Analyze session consistency for tampering detection
  static bool _analyzeSessionConsistency(String lastSession, String currentSession) {
    // For now, just check if sessions are different (which is expected)
    // In a real implementation, you'd analyze the underlying data
    return lastSession != currentSession;
  }

  /// Validate NFC interaction authenticity
  static Future<SpoofingValidationResult> validateNFCInteraction({
    required String tokenId,
    required String operationType,
    Map<String, dynamic>? additionalContext,
  }) async {
    print('🔍 ANTI-SPOOFING: Validating NFC interaction');
    print('   Token: $tokenId');
    print('   Operation: $operationType');

    final validations = <String, bool>{};
    final warnings = <String>[];
    final errors = <String>[];
    
    // Step 0: GPS location validation (if applicable)
    try {
      final locationResult = await LocationSecurityValidator.validateLocationSecurity(
        operationType: operationType,
        transactionValue: additionalContext?['transaction_value']?.toDouble(),
        additionalContext: additionalContext,
      );
      
      validations['location_security'] = locationResult.allowOperation;
      if (!locationResult.allowOperation) {
        errors.add('Location security failed: ${locationResult.blockingReason}');
      } else if (locationResult.hasWarnings) {
        warnings.addAll(locationResult.warnings);
      }
      
      // Add location context to additional context
      additionalContext = {
        ...?additionalContext,
        'location_score': locationResult.locationSecurityScore,
        'location_secure': locationResult.isSecure,
      };
      
    } catch (e) {
      warnings.add('Location validation error: $e');
    }

    // 1. Device fingerprint validation
    if (_deviceFingerprint == null) {
      errors.add('Device fingerprint not initialized');
    } else {
      validations['device_fingerprint'] = true;
    }

    // 2. Biometric validation (if available)
    try {
      final isAvailable = await _localAuth.isDeviceSupported();
      if (isAvailable) {
        final biometricTypes = await _localAuth.getAvailableBiometrics();
        if (biometricTypes.isNotEmpty) {
          final authenticated = await _localAuth.authenticate(
            localizedReason: 'Verify your identity for secure token interaction',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );
          
          validations['biometric_auth'] = authenticated;
          if (!authenticated) {
            errors.add('Biometric authentication failed');
          }
        } else {
          warnings.add('No biometric methods available');
        }
      } else {
        warnings.add('Biometric authentication not supported');
      }
    } catch (e) {
      warnings.add('Biometric validation error: $e');
    }

    // 3. Behavioral analysis
    final behaviorScore = _analyzeBehavior(operationType, additionalContext);
    validations['behavior_analysis'] = behaviorScore >= 0.7;
    
    if (behaviorScore < 0.5) {
      errors.add('Suspicious behavioral pattern detected');
    } else if (behaviorScore < 0.7) {
      warnings.add('Unusual behavioral pattern observed');
    }

    // 4. Session timing analysis
    final timingValid = _validateInteractionTiming();
    validations['timing_analysis'] = timingValid;
    if (!timingValid) {
      warnings.add('Unusual interaction timing detected');
    }

    // 5. Location consistency (if available)
    // This would integrate with location services in a real implementation
    validations['location_consistency'] = true;

    // Update behavior profile
    await _updateBehaviorProfile(operationType, validations, warnings, errors);

    // Calculate overall trust score
    final validCount = validations.values.where((v) => v).length;
    final totalChecks = validations.length;
    final trustScore = totalChecks > 0 ? validCount / totalChecks : 0.0;

    final result = SpoofingValidationResult(
      isValid: errors.isEmpty && trustScore >= 0.8,
      trustScore: trustScore,
      validations: validations,
      warnings: warnings,
      errors: errors,
      deviceFingerprint: _deviceFingerprint,
      behaviorScore: behaviorScore,
    );

    // Report high-risk activities
    if (trustScore < 0.6 || errors.isNotEmpty) {
      await _reportSuspiciousActivity('nfc_validation_failed', {
        'token_id': tokenId,
        'operation': operationType,
        'trust_score': trustScore,
        'errors': errors,
        'validations': validations,
      });
    }

    return result;
  }

  /// Analyze user behavior patterns
  static double _analyzeBehavior(String operationType, Map<String, dynamic>? context) {
    if (_behaviorProfile == null) return 0.5; // Neutral score if no profile

    double score = 1.0;

    // Analyze operation frequency patterns
    final scanPatterns = Map<String, int>.from(_behaviorProfile!['scan_patterns'] ?? {});
    final operationCount = scanPatterns[operationType] ?? 0;
    final totalOperations = scanPatterns.values.fold(0, (sum, count) => sum + count);

    if (totalOperations > 10) {
      final frequency = operationCount / totalOperations;
      if (frequency < 0.05 && operationType != 'read') {
        score -= 0.2; // Unusual operation for this user
      }
    }

    // Analyze session patterns
    final sessionDurations = List<int>.from(_behaviorProfile!['session_durations'] ?? []);
    if (sessionDurations.isNotEmpty) {
      final avgDuration = sessionDurations.reduce((a, b) => a + b) / sessionDurations.length;
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      
      // Check if current session duration is extremely different
      if (sessionDurations.length > 5) {
        final deviation = (currentTime - avgDuration).abs() / avgDuration;
        if (deviation > 2.0) {
          score -= 0.1; // Unusual session duration
        }
      }
    }

    // Analyze interaction timing patterns
    final interactionTimings = List<int>.from(_behaviorProfile!['interaction_timings'] ?? []);
    if (interactionTimings.isNotEmpty && interactionTimings.length > 3) {
      final avgInterval = _calculateAverageInterval(interactionTimings);
      final lastTiming = interactionTimings.last;
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final currentInterval = currentTime - lastTiming;
      
      if (avgInterval > 0) {
        final intervalDeviation = (currentInterval - avgInterval).abs() / avgInterval;
        if (intervalDeviation > 5.0) {
          score -= 0.15; // Very unusual timing pattern
        }
      }
    }

    return math.max(0.0, math.min(1.0, score));
  }

  /// Calculate average interval between interactions
  static double _calculateAverageInterval(List<int> timings) {
    if (timings.length < 2) return 0;
    
    double totalInterval = 0;
    for (int i = 1; i < timings.length; i++) {
      totalInterval += timings[i] - timings[i - 1];
    }
    
    return totalInterval / (timings.length - 1);
  }

  /// Validate interaction timing for bot detection
  static bool _validateInteractionTiming() {
    // Simple timing validation - in real implementation, this would be more sophisticated
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    
    if (_behaviorProfile != null) {
      final interactionTimings = List<int>.from(_behaviorProfile!['interaction_timings'] ?? []);
      if (interactionTimings.isNotEmpty) {
        final lastInteraction = interactionTimings.last;
        final timeSinceLastInteraction = currentTime - lastInteraction;
        
        // Flag if interactions are too rapid (< 1 second) or too regular
        if (timeSinceLastInteraction < 1000) {
          return false; // Too rapid for human interaction
        }
        
        // Check for robotic timing patterns
        if (interactionTimings.length >= 3) {
          final intervals = <int>[];
          for (int i = 1; i < interactionTimings.length; i++) {
            intervals.add(interactionTimings[i] - interactionTimings[i - 1]);
          }
          
          // Check for suspiciously consistent intervals (±100ms)
          final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
          final allSimilar = intervals.every((interval) => 
              (interval - avgInterval).abs() < 100);
          
          if (allSimilar && intervals.length > 5) {
            return false; // Too consistent - likely automated
          }
        }
      }
    }
    
    return true;
  }

  /// Update behavior profile with new interaction data
  static Future<void> _updateBehaviorProfile(
    String operationType,
    Map<String, bool> validations,
    List<String> warnings,
    List<String> errors,
  ) async {
    if (_behaviorProfile == null) return;

    final currentTime = DateTime.now().millisecondsSinceEpoch;

    // Update scan patterns
    final scanPatterns = Map<String, int>.from(_behaviorProfile!['scan_patterns'] ?? {});
    scanPatterns[operationType] = (scanPatterns[operationType] ?? 0) + 1;
    _behaviorProfile!['scan_patterns'] = scanPatterns;

    // Update interaction timings
    final interactionTimings = List<int>.from(_behaviorProfile!['interaction_timings'] ?? []);
    interactionTimings.add(currentTime);
    
    // Keep only last 50 interactions to prevent data bloat
    if (interactionTimings.length > 50) {
      interactionTimings.removeRange(0, interactionTimings.length - 50);
    }
    _behaviorProfile!['interaction_timings'] = interactionTimings;

    // Update error frequencies
    if (errors.isNotEmpty) {
      final errorFrequencies = Map<String, int>.from(_behaviorProfile!['error_frequencies'] ?? {});
      for (final error in errors) {
        errorFrequencies[error] = (errorFrequencies[error] ?? 0) + 1;
      }
      _behaviorProfile!['error_frequencies'] = errorFrequencies;
    }

    // Update session count
    _behaviorProfile!['total_sessions'] = (_behaviorProfile!['total_sessions'] ?? 0) + 1;
    _behaviorProfile!['last_updated'] = currentTime;

    await _saveBehaviorProfile();
  }

  /// Report suspicious activity to security monitoring
  static Future<void> _reportSuspiciousActivity(
    String activityType,
    Map<String, dynamic> details,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final deviceFingerprint = _deviceFingerprint ?? 'unknown';
      
      final report = {
        'activity_type': activityType,
        'details': details,
        'device_fingerprint': deviceFingerprint,
        'user_id': user?.uid ?? 'anonymous',
        'timestamp': FieldValue.serverTimestamp(),
        'platform': Platform.operatingSystem,
        'app_version': await _getAppVersion(),
      };

      await _firestore.collection('security_incidents').add(report);
      
      print('🚨 SECURITY: Suspicious activity reported: $activityType');
      
    } catch (e) {
      print('⚠️ SECURITY: Failed to report suspicious activity: $e');
    }
  }

  /// Get current app version
  static Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      return 'unknown';
    }
  }

  /// Get device fingerprint for external validation
  static String? getDeviceFingerprint() => _deviceFingerprint;

  /// Get behavior profile summary
  static Map<String, dynamic>? getBehaviorProfile() => _behaviorProfile;

  /// Clear behavior profile (for testing or user reset)
  static Future<void> clearBehaviorProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_behaviorProfileKey);
    _behaviorProfile = null;
    await _loadBehaviorProfile();
  }
}

/// Result of anti-spoofing validation
class SpoofingValidationResult {
  final bool isValid;
  final double trustScore;
  final Map<String, bool> validations;
  final List<String> warnings;
  final List<String> errors;
  final String? deviceFingerprint;
  final double behaviorScore;

  SpoofingValidationResult({
    required this.isValid,
    required this.trustScore,
    required this.validations,
    required this.warnings,
    required this.errors,
    this.deviceFingerprint,
    required this.behaviorScore,
  });

  @override
  String toString() {
    return 'SpoofingValidationResult(isValid: $isValid, trustScore: $trustScore, '
           'warnings: ${warnings.length}, errors: ${errors.length})';
  }
} 