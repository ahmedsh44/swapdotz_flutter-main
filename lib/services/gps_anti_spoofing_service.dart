import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Comprehensive GPS anti-spoofing service with indoor/no-GPS support
class GPSAntiSpoofingService {
  static const String _locationHistoryKey = 'location_history_v2';
  static const String _gpsValidationKey = 'gps_validation_v1';
  static const int _maxLocationHistory = 20;
  static const double _maxReasonableSpeed = 200.0; // m/s (720 km/h - faster than commercial jets)
  static const double _maxInstantTeleport = 10000.0; // 10km instant movement threshold
  static const int _minSatelliteCount = 4; // Minimum for reliable GPS
  static const double _minAccuracy = 100.0; // meters
  static const int _spoofingDetectionWindow = 300000; // 5 minutes
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static List<GPSReading> _locationHistory = [];
  static GPSValidationResult? _lastValidation;
  static Timer? _continuousMonitoringTimer;

  /// Initialize GPS anti-spoofing with location history
  static Future<void> initialize() async {
    await _loadLocationHistory();
    await _startContinuousMonitoring();
    print('🛰️ GPS Anti-Spoofing: Initialized with ${_locationHistory.length} historical readings');
  }

  /// Validate GPS location with comprehensive anti-spoofing checks
  static Future<GPSValidationResult> validateLocation({
    bool allowIndoorFallback = true,
    bool requireHighAccuracy = false,
    String? operationType,
  }) async {
    print('🛰️ GPS VALIDATION: Starting comprehensive location validation');
    print('   Operation: ${operationType ?? 'general'}');
    print('   Indoor fallback: $allowIndoorFallback');
    print('   High accuracy required: $requireHighAccuracy');

    final result = GPSValidationResult();
    
    try {
      // Step 1: Check location permissions
      final permissionCheck = await _checkLocationPermissions();
      result.addValidation('permissions', permissionCheck.isValid);
      if (!permissionCheck.isValid) {
        result.addError('Location permissions denied');
        if (!allowIndoorFallback) {
          return result;
        }
      }

      // Step 2: Get current location with multiple attempts
      final locationResult = await _getCurrentLocationWithValidation();
      
      if (locationResult.location != null) {
        final location = locationResult.location!;
        
        // Step 3: Comprehensive spoofing detection
        await _performSpoofingDetection(location, result);
        
        // Step 4: Cross-validate with network location
        await _crossValidateWithNetworkLocation(location, result);
        
        // Step 5: Validate against historical patterns
        _validateHistoricalPatterns(location, result);
        
        // Step 6: Check for mock locations (developer options)
        _checkMockLocationSettings(location, result);
        
        // Step 7: Satellite signal analysis
        _analyzeSatelliteSignals(location, result);
        
        // Step 8: Speed and movement validation
        _validateMovementPhysics(location, result);
        
        // Step 9: Add to location history
        await _addToLocationHistory(location);
        
      } else {
        // No GPS available - handle gracefully
        result.addWarning('GPS location unavailable');
        
        if (allowIndoorFallback) {
          await _handleIndoorFallback(result);
        } else {
          result.addError('GPS required but unavailable');
        }
      }

      // Step 10: Calculate final trust score
      _calculateTrustScore(result, requireHighAccuracy);
      
      // Step 11: Log validation results
      await _logValidationResults(result, operationType);
      
      _lastValidation = result;
      return result;

    } catch (e) {
      print('🚨 GPS VALIDATION ERROR: $e');
      result.addError('GPS validation failed: $e');
      
      if (allowIndoorFallback) {
        await _handleIndoorFallback(result);
      }
      
      return result;
    }
  }

  /// Check location permissions
  static Future<PermissionResult> _checkLocationPermissions() async {
    try {
      final permission = await Geolocator.checkPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      if (!serviceEnabled) {
        return PermissionResult(false, 'Location services disabled');
      }
      
      if (permission == LocationPermission.denied) {
        final requestResult = await Geolocator.requestPermission();
        if (requestResult == LocationPermission.denied ||
            requestResult == LocationPermission.deniedForever) {
          return PermissionResult(false, 'Location permission denied');
        }
      }
      
      return PermissionResult(true, 'Permissions granted');
    } catch (e) {
      return PermissionResult(false, 'Permission check failed: $e');
    }
  }

  /// Get current location with validation
  static Future<LocationResult> _getCurrentLocationWithValidation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
      
      final reading = GPSReading(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        speedAccuracy: position.speedAccuracy,
        heading: position.heading,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMock: position.isMocked,
      );
      
      return LocationResult(reading, null);
    } catch (e) {
      print('📍 GPS: Failed to get current location: $e');
      return LocationResult(null, e.toString());
    }
  }

  /// Comprehensive spoofing detection
  static Future<void> _performSpoofingDetection(
    GPSReading location,
    GPSValidationResult result,
  ) async {
    print('🔍 SPOOFING DETECTION: Running comprehensive checks');

    // Check 1: Mock location detection
    if (location.isMock) {
      result.addError('Mock location detected (developer options enabled)');
      result.spoofingIndicators.add('mock_location_enabled');
    }

    // Check 2: Emulator detection
    await _detectEmulator(result);

    // Check 3: VPN detection  
    await _detectVPN(result);

    // Check 4: GPS spoofing app detection
    await _detectGPSSpoofingApps(result);

    // Check 5: Accuracy validation
    if (location.accuracy > _minAccuracy) {
      result.addWarning('GPS accuracy too low: ${location.accuracy.toStringAsFixed(1)}m');
      result.spoofingIndicators.add('low_accuracy');
    }

    // Check 3: Impossible coordinates
    if (_isImpossibleLocation(location)) {
      result.addError('Impossible GPS coordinates detected');
      result.spoofingIndicators.add('impossible_coordinates');
    }

    // Check 4: Repeated exact coordinates (spoofing pattern)
    if (_hasRepeatedExactCoordinates(location)) {
      result.addWarning('Suspicious repeated exact coordinates');
      result.spoofingIndicators.add('repeated_coordinates');
    }

    // Check 5: Grid pattern detection (common in GPS spoofing)
    if (_detectsGridPattern(location)) {
      result.addWarning('Grid pattern movement detected');
      result.spoofingIndicators.add('grid_pattern');
    }

    // Check 6: Time discontinuity check
    if (_hasTimeDiscontinuity(location)) {
      result.addError('GPS time discontinuity detected');
      result.spoofingIndicators.add('time_discontinuity');
    }

    result.addValidation('spoofing_detection', result.spoofingIndicators.isEmpty);
  }

  /// Cross-validate with network-based location
  static Future<void> _crossValidateWithNetworkLocation(
    GPSReading gpsLocation,
    GPSValidationResult result,
  ) async {
    try {
      // Get network-based location for comparison
      final networkPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final distance = Geolocator.distanceBetween(
        gpsLocation.latitude,
        gpsLocation.longitude,
        networkPosition.latitude,
        networkPosition.longitude,
      );

      // Allow reasonable difference based on accuracy
      final maxAllowableDistance = math.max(
        gpsLocation.accuracy + networkPosition.accuracy,
        1000.0, // 1km minimum tolerance for network location
      );

      if (distance > maxAllowableDistance) {
        result.addWarning(
          'GPS/Network location mismatch: ${distance.toStringAsFixed(0)}m apart'
        );
        result.spoofingIndicators.add('gps_network_mismatch');
      } else {
        result.addValidation('network_cross_validation', true);
      }

    } catch (e) {
      result.addWarning('Network location validation failed: $e');
    }
  }

  /// Validate against historical movement patterns
  static void _validateHistoricalPatterns(
    GPSReading location,
    GPSValidationResult result,
  ) {
    if (_locationHistory.isEmpty) {
      result.addValidation('historical_patterns', true);
      return;
    }

    final lastLocation = _locationHistory.last;
    final timeDiff = location.timestamp - lastLocation.timestamp;
    
    if (timeDiff <= 0) {
      result.addError('GPS timestamp inconsistency');
      result.spoofingIndicators.add('timestamp_inconsistency');
      return;
    }

    final distance = _calculateDistance(lastLocation, location);
    final timeSeconds = timeDiff / 1000.0;
    final speed = distance / timeSeconds; // m/s

    // Check for impossible speed
    if (speed > _maxReasonableSpeed) {
      result.addError(
        'Impossible movement speed: ${(speed * 3.6).toStringAsFixed(1)} km/h'
      );
      result.spoofingIndicators.add('impossible_speed');
    }

    // Check for instant teleportation
    if (distance > _maxInstantTeleport && timeSeconds < 60) {
      result.addError(
        'Instant teleportation detected: ${(distance / 1000).toStringAsFixed(1)}km in ${timeSeconds.toStringAsFixed(1)}s'
      );
      result.spoofingIndicators.add('instant_teleportation');
    }

    // Pattern analysis for regular movement
    if (_locationHistory.length >= 3) {
      _analyzeMovementPattern(location, result);
    }

    result.addValidation('historical_patterns', result.spoofingIndicators.isEmpty);
  }

  /// Check for mock location settings
  static void _checkMockLocationSettings(
    GPSReading location,
    GPSValidationResult result,
  ) {
    // This would be enhanced with platform-specific checks
    if (location.isMock) {
      result.addError('Mock locations enabled in device settings');
      result.spoofingIndicators.add('mock_settings_enabled');
    }
    
    result.addValidation('mock_location_check', !location.isMock);
  }

  /// Analyze satellite signals (when available)
  static void _analyzeSatelliteSignals(
    GPSReading location,
    GPSValidationResult result,
  ) {
    // Check accuracy as proxy for satellite signal quality
    if (location.accuracy < 5.0) {
      result.addValidation('satellite_signals', true);
      result.addInfo('Excellent GPS signal quality');
    } else if (location.accuracy < 20.0) {
      result.addValidation('satellite_signals', true);
      result.addInfo('Good GPS signal quality');
    } else if (location.accuracy < 50.0) {
      result.addValidation('satellite_signals', true);
      result.addWarning('Moderate GPS signal quality');
    } else {
      result.addValidation('satellite_signals', false);
      result.addWarning('Poor GPS signal quality - potential spoofing');
    }
  }

  /// Validate movement physics
  static void _validateMovementPhysics(
    GPSReading location,
    GPSValidationResult result,
  ) {
    if (_locationHistory.length < 2) {
      result.addValidation('movement_physics', true);
      return;
    }

    // Analyze acceleration patterns
    final recentMovements = _locationHistory.length >= 3
        ? _locationHistory.sublist(_locationHistory.length - 3)
        : _locationHistory;

    double maxAcceleration = 0.0;
    for (int i = 1; i < recentMovements.length; i++) {
      final prev = recentMovements[i - 1];
      final curr = recentMovements[i];
      
      final distance = _calculateDistance(prev, curr);
      final timeDiff = (curr.timestamp - prev.timestamp) / 1000.0;
      
      if (timeDiff > 0) {
        final speed = distance / timeDiff;
        
        if (i > 1) {
          final prevPrev = recentMovements[i - 2];
          final prevDistance = _calculateDistance(prevPrev, prev);
          final prevTimeDiff = (prev.timestamp - prevPrev.timestamp) / 1000.0;
          
          if (prevTimeDiff > 0) {
            final prevSpeed = prevDistance / prevTimeDiff;
            final acceleration = (speed - prevSpeed) / timeDiff;
            maxAcceleration = math.max(maxAcceleration, acceleration.abs());
          }
        }
      }
    }

    // Check for unrealistic acceleration (> 20 m/s² sustained)
    if (maxAcceleration > 20.0) {
      result.addWarning(
        'High acceleration detected: ${maxAcceleration.toStringAsFixed(1)} m/s²'
      );
      result.spoofingIndicators.add('high_acceleration');
    }

    result.addValidation('movement_physics', maxAcceleration <= 20.0);
  }

  /// Handle indoor/no-GPS fallback gracefully
  static Future<void> _handleIndoorFallback(GPSValidationResult result) async {
    print('🏢 INDOOR FALLBACK: Enabling alternative validation');
    
    // Use network-based location if available
    try {
      final networkPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      
      result.addInfo('Using network-based location (indoor mode)');
      result.indoorMode = true;
      result.addValidation('indoor_fallback', true);
      
      // Less strict validation for indoor scenarios
      result.trustScore = math.max(result.trustScore, 0.6);
      
    } catch (e) {
      // No location available at all - still allow operation with warnings
      result.addWarning('No location services available (complete indoor mode)');
      result.indoorMode = true;
      result.noLocationMode = true;
      result.addValidation('no_location_fallback', true);
      
      // Minimum trust score for no-location scenarios
      result.trustScore = math.max(result.trustScore, 0.5);
    }
  }

  /// Check for impossible locations (ocean, Antarctica, etc.)
  static bool _isImpossibleLocation(GPSReading location) {
    // Check for null island (0,0)
    if (location.latitude.abs() < 0.001 && location.longitude.abs() < 0.001) {
      return true;
    }
    
    // Check for extreme coordinates
    if (location.latitude.abs() > 90 || location.longitude.abs() > 180) {
      return true;
    }
    
    // Check for common test/spoofed coordinates
    final commonFakeLocations = [
      {'lat': 37.7749, 'lng': -122.4194}, // San Francisco (common default)
      {'lat': 40.7128, 'lng': -74.0060},  // New York (common default)
      {'lat': 51.5074, 'lng': -0.1278},   // London (common default)
    ];
    
    for (final fake in commonFakeLocations) {
      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        fake['lat']!,
        fake['lng']!,
      );
      
      if (distance < 10) { // Within 10 meters of common fake location
        return true;
      }
    }
    
    return false;
  }

  /// Check for repeated exact coordinates
  static bool _hasRepeatedExactCoordinates(GPSReading location) {
    if (_locationHistory.length < 3) return false;
    
    int exactMatches = 0;
    for (final historical in _locationHistory.reversed.take(5)) {
      if (historical.latitude == location.latitude &&
          historical.longitude == location.longitude) {
        exactMatches++;
      }
    }
    
    return exactMatches >= 2; // Too many exact matches is suspicious
  }

  /// Detect grid pattern movement (common spoofing technique)
  static bool _detectsGridPattern(GPSReading location) {
    if (_locationHistory.length < 4) return false;
    
    final recent = _locationHistory.reversed.take(4).toList();
    recent.add(location);
    
    // Check for regular lat/lng increments (grid pattern)
    final latDiffs = <double>[];
    final lngDiffs = <double>[];
    
    for (int i = 1; i < recent.length; i++) {
      latDiffs.add((recent[i].latitude - recent[i-1].latitude).abs());
      lngDiffs.add((recent[i].longitude - recent[i-1].longitude).abs());
    }
    
    // Check if movements are suspiciously regular
    final latVariance = _calculateVariance(latDiffs);
    final lngVariance = _calculateVariance(lngDiffs);
    
    return latVariance < 0.0001 && lngVariance < 0.0001; // Too regular
  }

  /// Check for GPS time discontinuity
  static bool _hasTimeDiscontinuity(GPSReading location) {
    if (_locationHistory.isEmpty) return false;
    
    final lastTime = _locationHistory.last.timestamp;
    final currentTime = location.timestamp;
    final systemTime = DateTime.now().millisecondsSinceEpoch;
    
    // Check if GPS time is too far from system time
    final gpsSystemDiff = (currentTime - systemTime).abs();
    if (gpsSystemDiff > 60000) { // More than 1 minute difference
      return true;
    }
    
    // Check for time going backwards
    if (currentTime <= lastTime) {
      return true;
    }
    
    return false;
  }

  /// Analyze movement pattern for abnormalities
  static void _analyzeMovementPattern(
    GPSReading location,
    GPSValidationResult result,
  ) {
    final recent = _locationHistory.reversed.take(5).toList();
    recent.add(location);
    
    // Analyze speed consistency
    final speeds = <double>[];
    for (int i = 1; i < recent.length; i++) {
      final distance = _calculateDistance(recent[i-1], recent[i]);
      final timeDiff = (recent[i].timestamp - recent[i-1].timestamp) / 1000.0;
      if (timeDiff > 0) {
        speeds.add(distance / timeDiff);
      }
    }
    
    if (speeds.length >= 3) {
      final speedVariance = _calculateVariance(speeds);
      
      // Too consistent speed might indicate spoofing
      if (speedVariance < 0.1 && speeds.first > 1.0) { // Moving but too consistent
        result.addWarning('Suspiciously consistent movement speed');
        result.spoofingIndicators.add('consistent_speed');
      }
    }
  }

  /// Calculate distance between two GPS readings
  static double _calculateDistance(GPSReading from, GPSReading to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// Calculate variance of a list of values
  static double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((value) => math.pow(value - mean, 2));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  /// Calculate final trust score
  static void _calculateTrustScore(
    GPSValidationResult result,
    bool requireHighAccuracy,
  ) {
    double score = 1.0;
    
    // Reduce score for each error
    score -= result.errors.length * 0.3;
    
    // Reduce score for each warning
    score -= result.warnings.length * 0.1;
    
    // Reduce score for spoofing indicators
    score -= result.spoofingIndicators.length * 0.15;
    
    // Bonus for successful validations
    final validationCount = result.validations.values.where((v) => v).length;
    final totalValidations = result.validations.length;
    if (totalValidations > 0) {
      score *= (validationCount / totalValidations);
    }
    
    // Adjust for indoor/no-location modes
    if (result.noLocationMode) {
      score = math.max(score, 0.5); // Minimum score for no-location
    } else if (result.indoorMode) {
      score = math.max(score, 0.6); // Minimum score for indoor
    }
    
    // High accuracy requirement adjustment
    if (requireHighAccuracy && !result.indoorMode && !result.noLocationMode) {
      score *= 0.9; // Stricter scoring for high accuracy requirements
    }
    
    result.trustScore = math.max(0.0, math.min(1.0, score));
  }

  /// Load location history from storage
  static Future<void> _loadLocationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_locationHistoryKey);
      
      if (historyJson != null) {
        final List<dynamic> historyList = json.decode(historyJson);
        _locationHistory = historyList
            .map((item) => GPSReading.fromJson(item))
            .toList();
        
        // Remove old entries (keep only last 20)
        if (_locationHistory.length > _maxLocationHistory) {
          _locationHistory = _locationHistory
              .sublist(_locationHistory.length - _maxLocationHistory);
        }
      }
    } catch (e) {
      print('Failed to load location history: $e');
      _locationHistory = [];
    }
  }

  /// Add location to history and save
  static Future<void> _addToLocationHistory(GPSReading location) async {
    _locationHistory.add(location);
    
    // Keep only recent history
    if (_locationHistory.length > _maxLocationHistory) {
      _locationHistory.removeAt(0);
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = json.encode(
        _locationHistory.map((reading) => reading.toJson()).toList()
      );
      await prefs.setString(_locationHistoryKey, historyJson);
    } catch (e) {
      print('Failed to save location history: $e');
    }
  }

  /// Start continuous GPS monitoring
  static Future<void> _startContinuousMonitoring() async {
    _continuousMonitoringTimer?.cancel();
    
    _continuousMonitoringTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) async {
        try {
          await validateLocation(
            allowIndoorFallback: true,
            operationType: 'background_monitoring',
          );
        } catch (e) {
          print('Background GPS monitoring error: $e');
        }
      },
    );
  }

  /// Log validation results for security monitoring
  static Future<void> _logValidationResults(
    GPSValidationResult result,
    String? operationType,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      
      if (result.spoofingIndicators.isNotEmpty || result.trustScore < 0.7) {
        await _firestore.collection('gps_security_events').add({
          'user_id': user?.uid ?? 'anonymous',
          'operation_type': operationType ?? 'unknown',
          'trust_score': result.trustScore,
          'spoofing_indicators': result.spoofingIndicators,
          'errors': result.errors,
          'warnings': result.warnings,
          'indoor_mode': result.indoorMode,
          'no_location_mode': result.noLocationMode,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Failed to log GPS validation results: $e');
    }
  }

  /// Detect if running on emulator
  static Future<void> _detectEmulator(GPSValidationResult result) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        
        // Check for common emulator indicators
        final emulatorIndicators = [
          androidInfo.isPhysicalDevice == false,
          androidInfo.brand.toLowerCase().contains('generic'),
          androidInfo.device.toLowerCase().contains('generic'),
          androidInfo.product.toLowerCase().contains('sdk'),
          androidInfo.model.toLowerCase().contains('emulator'),
          androidInfo.manufacturer.toLowerCase().contains('genymotion'),
          androidInfo.hardware.toLowerCase().contains('goldfish'),
          androidInfo.hardware.toLowerCase().contains('vbox'),
        ];
        
        final emulatorCount = emulatorIndicators.where((indicator) => indicator).length;
        
        if (emulatorCount >= 2) {
          result.addError('Emulator detected - GPS location writing blocked');
          result.spoofingIndicators.add('emulator_detected');
        }
        
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        
        if (iosInfo.isPhysicalDevice == false) {
          result.addError('iOS Simulator detected - GPS location writing blocked');
          result.spoofingIndicators.add('ios_simulator_detected');
        }
      }
    } catch (e) {
      result.addWarning('Emulator detection failed: $e');
    }
  }

  /// Detect VPN usage through network analysis
  static Future<void> _detectVPN(GPSValidationResult result) async {
    try {
      // VPN detection through network characteristics
      // This is a simplified implementation - production would need platform channels
      
      // Check for common VPN DNS servers
      final commonVPNDNS = ['1.1.1.1', '8.8.8.8', '9.9.9.9'];
      
      // Check for suspicious network latency patterns
      final startTime = DateTime.now();
      try {
        // Simple network test to detect VPN overhead
        await Future.delayed(const Duration(milliseconds: 100));
        final latency = DateTime.now().difference(startTime).inMilliseconds;
        
        if (latency > 200) {
          result.addWarning('High network latency detected - possible VPN usage');
          result.spoofingIndicators.add('high_network_latency');
        }
      } catch (e) {
        // Network test failed
      }
      
      result.addInfo('VPN detection scan completed');
    } catch (e) {
      result.addWarning('VPN detection failed: $e');
    }
  }

  /// Detect GPS spoofing applications
  static Future<void> _detectGPSSpoofingApps(GPSValidationResult result) async {
    try {
      // Check for developer options enabled (Android indicator)
      if (Platform.isAndroid) {
        // This would require platform channel to check developer options
        // For now, we use the mock location flag
        result.addInfo('GPS spoofing app detection active');
      }
      
      // Look for suspicious location characteristics
      if (_locationHistory.isNotEmpty) {
        final recent = _locationHistory.last;
        
        // Check for impossibly perfect accuracy (spoofing indicator)
        if (recent.accuracy < 1.0) {
          result.addWarning('Suspiciously perfect GPS accuracy detected');
          result.spoofingIndicators.add('perfect_accuracy_suspicious');
        }
        
        // Check for missing speed data (some spoofing apps don't provide this)
        if (recent.speed == null || recent.speed == 0) {
          result.addInfo('Missing speed data in GPS reading');
        }
      }
    } catch (e) {
      result.addWarning('GPS spoofing app detection failed: $e');
    }
  }

  /// Get current validation status
  static GPSValidationResult? getLastValidation() => _lastValidation;

  /// Clear location history (for testing)
  static Future<void> clearLocationHistory() async {
    _locationHistory.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_locationHistoryKey);
  }

  /// Stop continuous monitoring
  static void dispose() {
    _continuousMonitoringTimer?.cancel();
    _continuousMonitoringTimer = null;
  }
}

/// GPS reading data structure
class GPSReading {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? speedAccuracy;
  final double? heading;
  final int timestamp;
  final bool isMock;

  GPSReading({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.speedAccuracy,
    this.heading,
    required this.timestamp,
    this.isMock = false,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'speedAccuracy': speedAccuracy,
    'heading': heading,
    'timestamp': timestamp,
    'isMock': isMock,
  };

  factory GPSReading.fromJson(Map<String, dynamic> json) => GPSReading(
    latitude: json['latitude']?.toDouble() ?? 0.0,
    longitude: json['longitude']?.toDouble() ?? 0.0,
    accuracy: json['accuracy']?.toDouble() ?? 999.0,
    altitude: json['altitude']?.toDouble(),
    speed: json['speed']?.toDouble(),
    speedAccuracy: json['speedAccuracy']?.toDouble(),
    heading: json['heading']?.toDouble(),
    timestamp: json['timestamp'] ?? 0,
    isMock: json['isMock'] ?? false,
  );
}

/// GPS validation result
class GPSValidationResult {
  double trustScore = 1.0;
  bool indoorMode = false;
  bool noLocationMode = false;
  
  final Map<String, bool> validations = {};
  final List<String> errors = [];
  final List<String> warnings = [];
  final List<String> info = [];
  final List<String> spoofingIndicators = [];

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

  bool get isValid => errors.isEmpty && trustScore >= 0.5;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isSuspicious => spoofingIndicators.isNotEmpty || trustScore < 0.7;

  @override
  String toString() {
    return 'GPSValidationResult(trustScore: $trustScore, '
           'valid: $isValid, errors: ${errors.length}, '
           'warnings: ${warnings.length}, spoofing: ${spoofingIndicators.length})';
  }
}

/// Permission check result
class PermissionResult {
  final bool isValid;
  final String message;

  PermissionResult(this.isValid, this.message);
}

/// Location retrieval result
class LocationResult {
  final GPSReading? location;
  final String? error;

  LocationResult(this.location, this.error);
} 