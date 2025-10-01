import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'trade_location_service.dart';
import 'firebase_service.dart';

/// Service to handle token trades with location validation
class TradeWithLocation {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Execute a token trade with location validation
  static Future<TradeResult> executeTrade({
    required BuildContext context,
    required String tokenId,
    required String toUserId,
    String? sessionId,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return TradeResult.error('User not authenticated');
      }

      print('🔄 TRADE: Starting trade with location validation');
      print('   Token: $tokenId');
      print('   From: ${currentUser.uid}');
      print('   To: $toUserId');

      // Step 1: Get location with validation
      final locationResult = await TradeLocationService.getTradeLocation(
        context: context,
        tokenId: tokenId,
        fromUser: currentUser.uid,
        toUser: toUserId,
      );

      // Check if user cancelled
      if (locationResult.cancelled) {
        print('❌ Trade cancelled by user during location validation');
        return TradeResult.cancelled('Trade cancelled by user');
      }

      // Step 2: Check travel achievement eligibility
      // Simple rule: if we have a location, we can earn achievements
      bool eligibleForAchievements = locationResult.hasLocation;

      // Step 3: Execute the ownership transfer
      print('🔄 Executing ownership transfer...');
      
      // This would call your existing transfer logic
      // For now, using a simplified version
      await _executeOwnershipTransfer(
        tokenId: tokenId,
        fromUser: currentUser.uid,
        toUser: toUserId,
        sessionId: sessionId,
      );

      // Step 4: Record trade with location data
      await TradeLocationService.recordTrade(
        tokenId: tokenId,
        fromUser: currentUser.uid,
        toUser: toUserId,
        locationResult: locationResult,
      );

      // Step 5: Process travel achievements if we have location
      if (locationResult.hasLocation) {
        await _processTravelAchievements(
          tokenId: tokenId,
          location: locationResult.location!,
          quality: locationResult.quality,
        );
      }

      // Step 6: Return success with details
      return TradeResult.success(
        tokenId: tokenId,
        hasLocation: locationResult.hasLocation,
        locationQuality: locationResult.quality,
        achievementsEarned: locationResult.hasLocation && eligibleForAchievements,
      );

    } catch (e) {
      print('❌ Trade error: $e');
      return TradeResult.error('Trade failed: $e');
    }
  }

  /// Execute the actual ownership transfer
  static Future<void> _executeOwnershipTransfer({
    required String tokenId,
    required String fromUser,
    required String toUser,
    String? sessionId,
  }) async {
    // This would integrate with your existing transfer logic
    // Using SwapDotzFirebaseService or similar
    
    if (sessionId != null) {
      // Complete existing transfer session
      await SwapDotzFirebaseService.completeTransfer(
        sessionId: sessionId,
        challengeResponse: '', // Your challenge logic
        newKeyHash: '', // Your key rotation logic
      );
    } else {
      // Direct transfer
      // Your existing transfer logic
    }
  }

  /// Process travel achievements based on location
  static Future<void> _processTravelAchievements({
    required String tokenId,
    required Position location,
    required LocationQuality quality,
  }) async {
    print('🏆 Processing travel achievements...');

    try {
      // Get or create achievement record for this token
      final achievementRef = _firestore.collection('travel_achievements').doc(tokenId);
      final achievementDoc = await achievementRef.get();

      Map<String, dynamic> achievements = {};
      if (achievementDoc.exists) {
        achievements = achievementDoc.data() ?? {};
      }

      // Determine location-based achievements
      final locationInfo = await _getLocationInfo(location);
      
      // Track cities visited
      List<String> citiesVisited = List<String>.from(achievements['cities_visited'] ?? []);
      if (locationInfo.city != null && !citiesVisited.contains(locationInfo.city)) {
        citiesVisited.add(locationInfo.city!);
        print('🏆 New city visited: ${locationInfo.city}');
      }

      // Track countries visited
      List<String> countriesVisited = List<String>.from(achievements['countries_visited'] ?? []);
      if (locationInfo.country != null && !countriesVisited.contains(locationInfo.country)) {
        countriesVisited.add(locationInfo.country!);
        print('🏆 New country visited: ${locationInfo.country}');
      }

      // Calculate total distance traveled
      double totalDistance = achievements['total_distance_km'] ?? 0.0;
      double distanceTraveled = 0.0;
      
      // Only calculate distance if we have a previous location with coordinates
      if (achievements['last_location'] != null) {
        final lastLat = achievements['last_location']['lat'];
        final lastLng = achievements['last_location']['lng'];
        
        distanceTraveled = _calculateDistance(
          lastLat, lastLng,
          location.latitude, location.longitude,
        );
        
        totalDistance += distanceTraveled;
        print('🏆 Distance traveled: ${distanceTraveled.toStringAsFixed(1)} km');
      } else {
        print('🏆 First location recorded for this token');
      }

      // Check for landmark achievements
      final landmark = await _checkLandmarkAchievement(location);
      List<String> landmarksVisited = List<String>.from(achievements['landmarks_visited'] ?? []);
      if (landmark != null && !landmarksVisited.contains(landmark)) {
        landmarksVisited.add(landmark);
        print('🏆 Landmark achievement: $landmark');
      }

      // Update achievements
      await achievementRef.set({
        'token_id': tokenId,
        'cities_visited': citiesVisited,
        'countries_visited': countriesVisited,
        'landmarks_visited': landmarksVisited,
        'total_distance_km': totalDistance,
        'total_trades': FieldValue.increment(1),
        'verified_trades': quality == LocationQuality.verified ? FieldValue.increment(1) : achievements['verified_trades'] ?? 0,
        'last_location': {
          'lat': location.latitude,
          'lng': location.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Calculate and update points
      await _updateLeaderboardPoints(tokenId, {
        'new_cities': citiesVisited.length - (achievements['cities_visited']?.length ?? 0),
        'new_countries': countriesVisited.length - (achievements['countries_visited']?.length ?? 0),
        'new_landmarks': landmark != null ? 1 : 0,
        'distance': distanceTraveled,
        'verified': quality == LocationQuality.verified,
      });

    } catch (e) {
      print('Error processing achievements: $e');
    }
  }

  /// Get location information (city, country) from coordinates
  static Future<LocationInfo> _getLocationInfo(Position location) async {
    // In production, this would use a reverse geocoding service
    // For now, returning placeholder data
    return LocationInfo(
      city: 'Paris',
      country: 'France',
      address: '123 Example Street',
    );
  }

  /// Check if location is near a landmark
  static Future<String?> _checkLandmarkAchievement(Position location) async {
    // Define landmark coordinates and radius
    final landmarks = {
      'Eiffel Tower': {'lat': 48.8584, 'lng': 2.2945, 'radius': 500},
      'Statue of Liberty': {'lat': 40.6892, 'lng': -74.0445, 'radius': 500},
      'Big Ben': {'lat': 51.5007, 'lng': -0.1246, 'radius': 500},
      // Add more landmarks
    };

    for (final entry in landmarks.entries) {
      final distance = _calculateDistance(
        entry.value['lat'] as double,
        entry.value['lng'] as double,
        location.latitude,
        location.longitude,
      ) * 1000; // Convert to meters

      if (distance <= (entry.value['radius'] as num)) {
        return entry.key;
      }
    }

    return null;
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

  /// Update leaderboard points based on achievements
  static Future<void> _updateLeaderboardPoints(String tokenId, Map<String, dynamic> achievements) async {
    int points = 0;

    // Points for new locations
    points += ((achievements['new_cities'] ?? 0) as num).toInt() * 50;
    points += ((achievements['new_countries'] ?? 0) as num).toInt() * 100;
    points += ((achievements['new_landmarks'] ?? 0) as num).toInt() * 200;
    
    // Points for distance
    points += (((achievements['distance'] ?? 0) as num) * 0.1).round(); // 0.1 point per km
    
    // Bonus for verified location
    if (achievements['verified']) {
      points = (points * 1.5).round(); // 50% bonus for verified GPS
    }

    if (points > 0) {
      // NOTE: Token updates should be done server-side, not client-side
      // Commenting out to avoid permission errors
      // await _firestore.collection('tokens').doc(tokenId).update({
      //   'metadata.leaderboard_points': FieldValue.increment(points),
      // });
      
      print('🏆 Leaderboard points earned: $points (not updated - requires server-side implementation)');
    }
  }
}

/// Trade result
class TradeResult {
  final bool success;
  final bool cancelled;
  final String? errorMessage;
  final String? tokenId;
  final bool hasLocation;
  final LocationQuality? locationQuality;
  final bool achievementsEarned;

  TradeResult._({
    required this.success,
    required this.cancelled,
    this.errorMessage,
    this.tokenId,
    required this.hasLocation,
    this.locationQuality,
    required this.achievementsEarned,
  });

  factory TradeResult.success({
    required String tokenId,
    required bool hasLocation,
    required LocationQuality locationQuality,
    required bool achievementsEarned,
  }) {
    return TradeResult._(
      success: true,
      cancelled: false,
      tokenId: tokenId,
      hasLocation: hasLocation,
      locationQuality: locationQuality,
      achievementsEarned: achievementsEarned,
    );
  }

  factory TradeResult.cancelled(String message) {
    return TradeResult._(
      success: false,
      cancelled: true,
      errorMessage: message,
      hasLocation: false,
      achievementsEarned: false,
    );
  }

  factory TradeResult.error(String message) {
    return TradeResult._(
      success: false,
      cancelled: false,
      errorMessage: message,
      hasLocation: false,
      achievementsEarned: false,
    );
  }
}

/// Location information
class LocationInfo {
  final String? city;
  final String? country;
  final String? address;

  LocationInfo({
    this.city,
    this.country,
    this.address,
  });
} 