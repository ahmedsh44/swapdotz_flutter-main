import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_security_validator.dart';
import 'gps_anti_spoofing_service.dart';

/// Specialized service for writing GPS location data to SwapDots with maximum anti-spoofing protection
class SwapDotLocationWriter {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Write current location to SwapDot with bulletproof anti-spoofing protection
  static Future<LocationWriteResult> writeLocationToSwapDot({
    required String tokenId,
    String? customLocationName,
    Map<String, dynamic>? additionalMetadata,
  }) async {
    print('📍 LOCATION WRITER: Starting GPS location write to SwapDot $tokenId');
    
    try {
      // Step 1: Maximum security validation for location writing
      final locationValidation = await LocationSecurityValidator.validateLocationSecurity(
        operationType: 'write_location_to_swapdot',
        additionalContext: {
          'token_id': tokenId,
          'custom_name': customLocationName,
          'user_id': _auth.currentUser?.uid,
        },
      );

      if (!locationValidation.allowOperation) {
        return LocationWriteResult.blocked(
          'Location writing blocked: ${locationValidation.blockingReason}',
          locationValidation.errors,
        );
      }

      // Step 2: Get current GPS location with high accuracy
      final position = await _getCurrentLocationWithMaxAccuracy();
      
      // Step 3: Perform additional validation on the obtained location
      final finalValidation = await _validateLocationForWriting(position);
      
      if (!finalValidation.isValid) {
        return LocationWriteResult.blocked(
          'Location validation failed: ${finalValidation.reason}',
          [finalValidation.reason],
        );
      }

      // Step 4: Write location data to SwapDot
      final locationData = await _writeLocationToFirestore(
        tokenId: tokenId,
        position: position,
        customName: customLocationName,
        metadata: additionalMetadata,
      );

      print('✅ LOCATION WRITER: Successfully wrote GPS location to SwapDot');
      
      return LocationWriteResult.success(locationData);

    } catch (e) {
      print('🚨 LOCATION WRITER ERROR: $e');
      return LocationWriteResult.error('Failed to write location: $e');
    }
  }

  /// Update travel location for SwapDot (when it changes location)
  static Future<LocationWriteResult> updateTravelLocation({
    required String tokenId,
    required String locationName,
    String? countryCode,
    String? cityName,
  }) async {
    print('🌍 LOCATION WRITER: Updating travel location for SwapDot $tokenId');
    
    try {
      // Step 1: Maximum security validation for travel update
      final locationValidation = await LocationSecurityValidator.validateLocationSecurity(
        operationType: 'update_travel_location',
        additionalContext: {
          'token_id': tokenId,
          'location_name': locationName,
          'country_code': countryCode,
          'city_name': cityName,
        },
      );

      if (!locationValidation.allowOperation) {
        return LocationWriteResult.blocked(
          'Travel location update blocked: ${locationValidation.blockingReason}',
          locationValidation.errors,
        );
      }

      // Step 2: Get GPS location for travel tracking
      final position = await _getCurrentLocationWithMaxAccuracy();
      
      // Step 3: Update travel stats in Firestore
      final travelData = await _updateTravelStats(
        tokenId: tokenId,
        position: position,
        locationName: locationName,
        countryCode: countryCode,
        cityName: cityName,
      );

      print('✅ LOCATION WRITER: Successfully updated travel location');
      
      return LocationWriteResult.success(travelData);

    } catch (e) {
      print('🚨 TRAVEL UPDATE ERROR: $e');
      return LocationWriteResult.error('Failed to update travel location: $e');
    }
  }

  /// Get current location with maximum accuracy and validation
  static Future<Position> _getCurrentLocationWithMaxAccuracy() async {
    print('📡 Getting GPS location with maximum accuracy...');
    
    try {
      // Use highest accuracy setting
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        forceAndroidLocationManager: false, // Use Google Play Services for better accuracy
        timeLimit: const Duration(seconds: 30),
      );

      print('📍 GPS Location obtained:');
      print('   Lat: ${position.latitude.toStringAsFixed(6)}');
      print('   Lng: ${position.longitude.toStringAsFixed(6)}');
      print('   Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
      print('   Speed: ${position.speed?.toStringAsFixed(1) ?? 'unknown'} m/s');
      print('   Mock: ${position.isMocked}');

      return position;
      
    } catch (e) {
      print('🚨 GPS location error: $e');
      rethrow;
    }
  }

  /// Perform final validation before writing location
  static Future<ValidationResult> _validateLocationForWriting(Position position) async {
    // Check 1: Mock location
    if (position.isMocked) {
      return ValidationResult.invalid('Mock GPS location detected');
    }

    // Check 2: Accuracy threshold
    if (position.accuracy > 50.0) { // 50 meter threshold for location writing
      return ValidationResult.invalid('GPS accuracy too low: ${position.accuracy.toStringAsFixed(1)}m');
    }

    // Check 3: Impossible coordinates
    if (position.latitude.abs() > 90 || position.longitude.abs() > 180) {
      return ValidationResult.invalid('Invalid GPS coordinates');
    }

    // Check 4: Null island (0,0)
    if (position.latitude.abs() < 0.001 && position.longitude.abs() < 0.001) {
      return ValidationResult.invalid('GPS coordinates at null island (0,0)');
    }

    // Check 5: Age of GPS fix
    final age = DateTime.now().difference(position.timestamp!).inSeconds;
    if (age > 30) { // GPS fix older than 30 seconds
      return ValidationResult.invalid('GPS fix too old: ${age}s');
    }

    return ValidationResult.valid();
  }

  /// Write location data to Firestore
  static Future<LocationData> _writeLocationToFirestore({
    required String tokenId,
    required Position position,
    String? customName,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final locationData = LocationData(
      tokenId: tokenId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp!,
      customName: customName,
      writtenBy: user.uid,
      writtenAt: DateTime.now(),
      metadata: metadata,
    );

    // Update token document with location
    await _firestore.collection('tokens').doc(tokenId).update({
      'current_location': locationData.toFirestore(),
      'last_location_update': FieldValue.serverTimestamp(),
      'location_history': FieldValue.arrayUnion([locationData.toFirestore()]),
    });

    // Log the location write event
    await _firestore.collection('location_write_events').add({
      'token_id': tokenId,
      'user_id': user.uid,
      'location_data': locationData.toFirestore(),
      'timestamp': FieldValue.serverTimestamp(),
      'security_validated': true,
    });

    return locationData;
  }

  /// Update travel statistics
  static Future<TravelData> _updateTravelStats({
    required String tokenId,
    required Position position,
    required String locationName,
    String? countryCode,
    String? cityName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final travelData = TravelData(
      tokenId: tokenId,
      locationName: locationName,
      countryCode: countryCode,
      cityName: cityName,
      latitude: position.latitude,
      longitude: position.longitude,
      visitedAt: DateTime.now(),
      visitedBy: user.uid,
    );

    // Update token travel stats
    final tokenRef = _firestore.collection('tokens').doc(tokenId);
    
    await _firestore.runTransaction((transaction) async {
      final tokenDoc = await transaction.get(tokenRef);
      if (!tokenDoc.exists) throw Exception('Token not found');

      final currentData = tokenDoc.data()!;
      final travelStats = Map<String, dynamic>.from(
        currentData['metadata']?['travel_stats'] ?? {}
      );

      // Update countries visited
      final countriesVisited = List<String>.from(travelStats['countries_visited'] ?? []);
      if (countryCode != null && !countriesVisited.contains(countryCode)) {
        countriesVisited.add(countryCode);
      }

      // Update cities visited
      final citiesVisited = List<String>.from(travelStats['cities_visited'] ?? []);
      final cityKey = cityName != null ? '$cityName, $countryCode' : locationName;
      if (!citiesVisited.contains(cityKey)) {
        citiesVisited.add(cityKey);
      }

      // Calculate total distance (simplified)
      final lastLocation = travelStats['last_location'];
      double totalDistance = travelStats['total_distance_km']?.toDouble() ?? 0.0;
      
      if (lastLocation != null) {
        final distance = Geolocator.distanceBetween(
          lastLocation['lat'],
          lastLocation['lng'],
          position.latitude,
          position.longitude,
        );
        totalDistance += distance / 1000; // Convert to km
      }

      // Update travel stats
      transaction.update(tokenRef, {
        'metadata.travel_stats': {
          'countries_visited': countriesVisited,
          'cities_visited': citiesVisited,
          'total_distance_km': totalDistance,
          'last_location': {
            'lat': position.latitude,
            'lng': position.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          },
        },
        'last_travel_update': FieldValue.serverTimestamp(),
      });
    });

    return travelData;
  }

  /// Check if location writing is supported for current environment
  static Future<bool> isLocationWritingSupported() async {
    try {
      // Check location permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return false;
      }

      // Check location services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      // Quick validation check
      final validation = await LocationSecurityValidator.validateLocationSecurity(
        operationType: 'write_location_to_swapdot',
      );

      return validation.allowOperation;
      
    } catch (e) {
      print('Location writing support check failed: $e');
      return false;
    }
  }

  /// Get human-readable message about location writing capability
  static Future<String> getLocationWritingStatus() async {
    final isSupported = await isLocationWritingSupported();
    
    if (isSupported) {
      return 'GPS location writing available';
    } else {
      try {
        final validation = await LocationSecurityValidator.validateLocationSecurity(
          operationType: 'write_location_to_swapdot',
        );
        
        if (!validation.allowOperation) {
          return validation.blockingReason ?? 'Location writing blocked for security';
        }
      } catch (e) {
        // Check specific issues
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          return 'Location permission required';
        }
        
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          return 'Location services disabled';
        }
      }
      
      return 'Location writing not available';
    }
  }
}

/// Result of location writing operation
class LocationWriteResult {
  final bool isSuccess;
  final LocationData? locationData;
  final TravelData? travelData;
  final String? errorMessage;
  final List<String> errors;

  LocationWriteResult._({
    required this.isSuccess,
    this.locationData,
    this.travelData,
    this.errorMessage,
    required this.errors,
  });

  factory LocationWriteResult.success(dynamic data) {
    if (data is LocationData) {
      return LocationWriteResult._(isSuccess: true, locationData: data, errors: []);
    } else if (data is TravelData) {
      return LocationWriteResult._(isSuccess: true, travelData: data, errors: []);
    } else {
      throw ArgumentError('Invalid data type for success result');
    }
  }

  factory LocationWriteResult.blocked(String reason, List<String> errors) {
    return LocationWriteResult._(
      isSuccess: false,
      errorMessage: reason,
      errors: errors,
    );
  }

  factory LocationWriteResult.error(String message) {
    return LocationWriteResult._(
      isSuccess: false,
      errorMessage: message,
      errors: [message],
    );
  }
}

/// Validation result for location data
class ValidationResult {
  final bool isValid;
  final String reason;

  ValidationResult._(this.isValid, this.reason);

  factory ValidationResult.valid() => ValidationResult._(true, '');
  factory ValidationResult.invalid(String reason) => ValidationResult._(false, reason);
}

/// Location data written to SwapDot
class LocationData {
  final String tokenId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final String? customName;
  final String writtenBy;
  final DateTime writtenAt;
  final Map<String, dynamic>? metadata;

  LocationData({
    required this.tokenId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    required this.timestamp,
    this.customName,
    required this.writtenBy,
    required this.writtenAt,
    this.metadata,
  });

  Map<String, dynamic> toFirestore() => {
    'token_id': tokenId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'timestamp': Timestamp.fromDate(timestamp),
    'custom_name': customName,
    'written_by': writtenBy,
    'written_at': Timestamp.fromDate(writtenAt),
    'metadata': metadata,
  };
}

/// Travel data for SwapDot journey tracking
class TravelData {
  final String tokenId;
  final String locationName;
  final String? countryCode;
  final String? cityName;
  final double latitude;
  final double longitude;
  final DateTime visitedAt;
  final String visitedBy;

  TravelData({
    required this.tokenId,
    required this.locationName,
    this.countryCode,
    this.cityName,
    required this.latitude,
    required this.longitude,
    required this.visitedAt,
    required this.visitedBy,
  });

  Map<String, dynamic> toFirestore() => {
    'token_id': tokenId,
    'location_name': locationName,
    'country_code': countryCode,
    'city_name': cityName,
    'latitude': latitude,
    'longitude': longitude,
    'visited_at': Timestamp.fromDate(visitedAt),
    'visited_by': visitedBy,
  };
} 