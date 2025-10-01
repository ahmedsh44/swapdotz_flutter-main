import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'gps_anti_spoofing_service.dart';
import 'location_fraud_detector.dart';

/// Smart trade location service that handles GPS validation and user choices
class TradeLocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Validate and get location for a trade with user choice fallback
  static Future<TradeLocationResult> getTradeLocation({
    required BuildContext context,
    required String tokenId,
    required String fromUser,
    required String toUser,
  }) async {
    print('📍 TRADE LOCATION: Starting location validation for trade');
    
    // Step 1: Try to get verified location
    final locationAttempt = await _attemptLocationCapture();
    
    // Step 2: Handle result based on location quality
    if (locationAttempt.isVerified) {
      // Good location - proceed automatically
      print('✅ Verified location obtained');
      return TradeLocationResult.withLocation(
        location: locationAttempt.location!,
        quality: locationAttempt.quality,
        source: locationAttempt.source,
      );
    } else if (locationAttempt.hasIssues) {
      // Location has issues - ask user
      print('⚠️ Location issues detected: ${locationAttempt.issues.join(", ")}');
      
      final userChoice = await _showLocationIssueDialog(
        context: context,
        issues: locationAttempt.issues,
        canUseApproximate: locationAttempt.location != null,
      );
      
      if (userChoice == LocationChoice.cancel) {
        return TradeLocationResult.cancelled();
      } else if (userChoice == LocationChoice.proceedWithoutLocation) {
        return TradeLocationResult.withoutLocation();
      } else if (userChoice == LocationChoice.useApproximate && locationAttempt.location != null) {
        return TradeLocationResult.withLocation(
          location: locationAttempt.location!,
          quality: LocationQuality.approximate,
          source: locationAttempt.source,
        );
      }
    }
    
    // Step 3: No location available - ask user
    print('📍 No location available');
    final proceed = await _showNoLocationDialog(context);
    
    if (proceed) {
      return TradeLocationResult.withoutLocation();
    } else {
      return TradeLocationResult.cancelled();
    }
  }

  /// Attempt to capture location with validation
  static Future<LocationAttempt> _attemptLocationCapture() async {
    final issues = <String>[];
    Position? bestLocation;
    String source = 'none';
    LocationQuality quality = LocationQuality.none;

    try {
      // Check location permissions
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        issues.add('Location permissions denied');
        return LocationAttempt(issues: issues);
      }

      // Check location services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        issues.add('Location services disabled');
        return LocationAttempt(issues: issues);
      }

      // Try GPS first (like Google Maps)
      try {
        print('📡 Attempting GPS location...');
        final gpsPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        // Check for GPS spoofing
        final spoofingCheck = await _checkGPSSpoofing(gpsPosition);
        
        if (spoofingCheck.isClean) {
          // GPS is clean, now check for advanced fraud patterns
          final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
          final fraudAnalysis = await LocationFraudDetector.analyzeLocation(
            userId: userId,
            currentPosition: gpsPosition,
            tokenId: '', // Will be provided in actual trade
          );
          
          if (!fraudAnalysis.isFraudulent) {
            // Clean GPS signal and no fraud detected - best case
            bestLocation = gpsPosition;
            source = 'gps';
            quality = LocationQuality.verified;
            print('✅ GPS location verified and clean');
          } else {
            // Advanced fraud patterns detected
            issues.addAll(fraudAnalysis.issues);
            print('🚫 ADVANCED FRAUD DETECTED: ${fraudAnalysis.issues}');
            print('   Fraud probability: ${(fraudAnalysis.fraudProbability * 100).toStringAsFixed(0)}%');
          }
        } else {
          // GPS spoofing detected
          issues.addAll(spoofingCheck.issues);
          print('⚠️ GPS spoofing detected: ${spoofingCheck.issues}');
        }
      } catch (e) {
        print('📡 GPS failed, trying network location...');
      }

      // If no good GPS, try network location
      if (bestLocation == null) {
        try {
          final networkPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 5),
          );

          // Check for VPN
          final vpnCheck = await _checkVPN();
          
          if (!vpnCheck.hasVPN) {
            // Network location without VPN - acceptable
            bestLocation = networkPosition;
            source = 'network';
            quality = LocationQuality.network;
            print('✅ Network location obtained (no VPN)');
          } else {
            // VPN detected with network location
            issues.add('VPN detected - location may be inaccurate');
            bestLocation = networkPosition; // Still capture but flag it
            source = 'network_vpn';
            quality = LocationQuality.suspicious;
            print('⚠️ Network location with VPN detected');
          }
        } catch (e) {
          print('❌ Network location also failed');
        }
      }

    } catch (e) {
      print('❌ Location capture error: $e');
      issues.add('Location capture failed: $e');
    }

    return LocationAttempt(
      location: bestLocation,
      quality: quality,
      source: source,
      issues: issues,
    );
  }

  /// Check for GPS spoofing indicators - COMPREHENSIVE
  static Future<SpoofingCheck> _checkGPSSpoofing(Position position) async {
    final issues = <String>[];
    
    // Check 1: Mock location flag (CRITICAL)
    if (position.isMocked) {
      issues.add('Mock location detected - disable developer options');
      print('🚫 SPOOFING: Mock location flag is true');
    }

    // Check 2: Emulator detection (CRITICAL)
    if (await _isEmulator()) {
      issues.add('Emulator detected - use physical device');
      print('🚫 SPOOFING: Running on emulator');
    }

    // Check 3: Suspicious accuracy patterns
    if (position.accuracy < 1.0) {
      issues.add('Suspicious GPS accuracy (too perfect)');
      print('⚠️ SPOOFING: Accuracy < 1m is suspicious');
    }
    
    // Check 4: Altitude validation (many spoofers report 0 or null)
    if (position.altitude == 0.0 || position.altitude == null) {
      issues.add('Missing altitude data (common in spoofing)');
      print('⚠️ SPOOFING: No altitude data');
    }

    // Check 5: Speed validation (instant teleportation)
    if (position.speed != null && position.speed! > 300) { // 300 m/s = 1080 km/h
      issues.add('Impossible speed detected');
      print('🚫 SPOOFING: Speed > 300 m/s');
    }

    // Check 6: Timestamp validation
    final now = DateTime.now().millisecondsSinceEpoch;
    final positionTime = position.timestamp?.millisecondsSinceEpoch ?? now;
    final timeDiff = (now - positionTime).abs();
    
    if (timeDiff > 30000) { // More than 30 seconds old
      issues.add('Stale GPS data (possible replay attack)');
      print('⚠️ SPOOFING: GPS data is ${timeDiff/1000}s old');
    }

    // Check 7: Provider validation (Android specific)
    if (Platform.isAndroid) {
      // GPS provider should be 'gps' or 'fused' for real GPS
      // 'network' alone is suspicious for high accuracy claims
      if (position.accuracy < 10 && position.speedAccuracy == null) {
        issues.add('GPS provider mismatch');
        print('⚠️ SPOOFING: High accuracy without speed accuracy');
      }
    }

    // Check 8: Check for known spoofing app signatures
    if (await _checkForSpoofingApps()) {
      issues.add('GPS spoofing app detected');
      print('🚫 SPOOFING: Known spoofing app found');
    }

    // Check 9: Coordinate validation (not 0,0 or test coordinates)
    if ((position.latitude == 0.0 && position.longitude == 0.0) ||
        (position.latitude == 37.4219983 && position.longitude == -122.084) || // Google HQ
        (position.latitude == 37.3318 && position.longitude == -122.0312)) { // Apple HQ
      issues.add('Test/default coordinates detected');
      print('🚫 SPOOFING: Known test coordinates');
    }
    
    return SpoofingCheck(
      isClean: issues.isEmpty,
      issues: issues,
    );
  }

  /// Check for known GPS spoofing apps
  static Future<bool> _checkForSpoofingApps() async {
    // This would use platform channels to check for:
    // - Fake GPS Location
    // - GPS Joystick
    // - Mock Locations
    // - Location Spoofer
    // etc.
    
    // For now, returning false (would implement via MethodChannel)
    return false;
  }

  /// Check for VPN usage - COMPREHENSIVE
  static Future<VPNCheck> _checkVPN() async {
    bool hasVPN = false;
    
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Check 1: Network interface names
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          final name = interface.name.toLowerCase();
          // Common VPN interface names
          if (name.contains('tun') || 
              name.contains('tap') || 
              name.contains('ppp') ||
              name.contains('vpn') ||
              name.contains('ipsec')) {
            hasVPN = true;
            print('🔒 VPN detected via interface: ${interface.name}');
            break;
          }
        }

        // Check 2: Check for VPN apps (would use MethodChannel)
        // Common VPN apps: ExpressVPN, NordVPN, Surfshark, etc.
        
        // Check 3: DNS server analysis
        // VPN services often use their own DNS servers
        
        // Check 4: MTU size check
        // VPNs often have different MTU sizes
        
        // Check 5: Latency patterns
        // VPNs typically add 20-100ms latency
      }
      
      return VPNCheck(hasVPN: hasVPN);
    } catch (e) {
      print('VPN check error: $e');
      // If we can't determine, assume VPN for safety
      return VPNCheck(hasVPN: true);
    }
  }

  /// Check if running on emulator
  static Future<bool> _isEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return !androidInfo.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
    } catch (e) {
      return false;
    }
    
    return false;
  }

  /// Show dialog when location has issues
  static Future<LocationChoice> _showLocationIssueDialog({
    required BuildContext context,
    required List<String> issues,
    required bool canUseApproximate,
  }) async {
    final result = await showDialog<LocationChoice>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Location Issues Detected'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The following issues were detected:'),
              const SizedBox(height: 12),
              ...issues.map((issue) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text(issue, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              const Text(
                'Trading without verified location means:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• No location achievements for this trade'),
              const Text('• Trade history won\'t show location'),
              const Text('• First future trade with GPS won\'t earn travel points'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(LocationChoice.cancel),
              child: const Text('Cancel Trade'),
            ),
            if (canUseApproximate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(LocationChoice.useApproximate),
                child: const Text('Use Approximate Location'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(LocationChoice.proceedWithoutLocation),
              child: const Text('Trade Without Location'),
            ),
          ],
        );
      },
    );
    
    return result ?? LocationChoice.cancel;
  }

  /// Show dialog when no location is available
  static Future<bool> _showNoLocationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.grey),
              SizedBox(width: 8),
              Text('No Location Available'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location services are unavailable. This could be because:'),
              SizedBox(height: 12),
              Text('• You\'re indoors with no GPS signal'),
              Text('• Location services are disabled'),
              Text('• Location permissions are denied'),
              SizedBox(height: 16),
              Text(
                'Trade without location?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• The trade will be recorded without coordinates'),
              Text('• No location achievements will be earned'),
              Text('• You can still complete the ownership transfer'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel Trade'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Trade Without Location'),
            ),
          ],
        );
      },
    );
    
    return result ?? false;
  }

  /// Record trade with location data (or without)
  static Future<void> recordTrade({
    required String tokenId,
    required String fromUser,
    required String toUser,
    required TradeLocationResult locationResult,
  }) async {
    final tradeData = <String, dynamic>{
      'token_id': tokenId,
      'from_user': fromUser,
      'to_user': toUser,
      'timestamp': FieldValue.serverTimestamp(),
      'trade_id': '${tokenId}_${DateTime.now().millisecondsSinceEpoch}',
    };

    // Add location data if available
    if (locationResult.hasLocation) {
      tradeData['location'] = {
        'latitude': locationResult.location!.latitude,
        'longitude': locationResult.location!.longitude,
        'accuracy': locationResult.location!.accuracy,
        'altitude': locationResult.location!.altitude,
        'quality': locationResult.quality.toString(),
        'source': locationResult.source,
      };

      // Check if eligible for travel achievements
      if (locationResult.quality == LocationQuality.verified || 
          locationResult.quality == LocationQuality.network) {
        tradeData['eligible_for_achievements'] = true;
      }
    } else {
      tradeData['location'] = null;
      tradeData['location_note'] = 'Trade completed without location';
      tradeData['eligible_for_achievements'] = false;
    }

    // Save trade record
    await _firestore.collection('trades').add(tradeData);

    // Update token's last trade location if available
    // NOTE: This should be done server-side, not client-side
    // Commenting out to avoid permission errors
    // if (locationResult.hasLocation) {
    //   await _firestore.collection('tokens').doc(tokenId).update({
    //     'last_trade_location': tradeData['location'],
    //     'last_trade_timestamp': FieldValue.serverTimestamp(),
    //   });
    // }
  }

  /// Calculate distance from last known location (if any)
  static Future<double?> calculateDistanceFromLastLocation(String tokenId, Position currentLocation) async {
    try {
      // Get last trade with location for this token
      final trades = await _firestore
          .collection('trades')
          .where('token_id', isEqualTo: tokenId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (trades.docs.isEmpty) {
        return null; // No previous location to calculate from
      }

      // Get last known location
      final lastTrade = trades.docs.first.data();
      final lastLocation = lastTrade['location'];
      
      if (lastLocation != null) {
        final lastLat = lastLocation['latitude'];
        final lastLng = lastLocation['longitude'];
        
        // Calculate distance in kilometers
        return _calculateDistance(
          lastLat, lastLng,
          currentLocation.latitude, currentLocation.longitude,
        );
      }

      return null;
    } catch (e) {
      print('Error calculating distance: $e');
      return null;
    }
  }

  /// Calculate distance between two coordinates in kilometers
  static double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    
    final double a = 
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
      math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degree) {
    return degree * (math.pi / 180);
  }
}

/// Result of location capture attempt
class LocationAttempt {
  final Position? location;
  final LocationQuality quality;
  final String source;
  final List<String> issues;

  LocationAttempt({
    this.location,
    this.quality = LocationQuality.none,
    this.source = 'none',
    required this.issues,
  });

  bool get isVerified => quality == LocationQuality.verified;
  bool get hasIssues => issues.isNotEmpty;
}

/// Location quality levels
enum LocationQuality {
  verified,    // GPS with no spoofing
  network,     // Network location without VPN
  approximate, // Network with minor issues
  suspicious,  // Has VPN or other issues
  none,        // No location available
}

/// User choice for location issues
enum LocationChoice {
  cancel,
  proceedWithoutLocation,
  useApproximate,
}

/// Trade location result
class TradeLocationResult {
  final bool hasLocation;
  final Position? location;
  final LocationQuality quality;
  final String source;
  final bool cancelled;

  TradeLocationResult._({
    required this.hasLocation,
    this.location,
    required this.quality,
    required this.source,
    required this.cancelled,
  });

  factory TradeLocationResult.withLocation({
    required Position location,
    required LocationQuality quality,
    required String source,
  }) {
    return TradeLocationResult._(
      hasLocation: true,
      location: location,
      quality: quality,
      source: source,
      cancelled: false,
    );
  }

  factory TradeLocationResult.withoutLocation() {
    return TradeLocationResult._(
      hasLocation: false,
      quality: LocationQuality.none,
      source: 'user_choice',
      cancelled: false,
    );
  }

  factory TradeLocationResult.cancelled() {
    return TradeLocationResult._(
      hasLocation: false,
      quality: LocationQuality.none,
      source: 'cancelled',
      cancelled: true,
    );
  }
}

/// Spoofing check result
class SpoofingCheck {
  final bool isClean;
  final List<String> issues;

  SpoofingCheck({
    required this.isClean,
    required this.issues,
  });
}

/// VPN check result
class VPNCheck {
  final bool hasVPN;

  VPNCheck({required this.hasVPN});
} 