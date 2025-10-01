import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Advanced location fraud detection using pattern analysis
class LocationFraudDetector {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Maximum realistic travel speed (commercial airline) in km/h
  static const double MAX_REALISTIC_SPEED = 900.0;
  
  /// Maximum ground travel speed in km/h
  static const double MAX_GROUND_SPEED = 300.0;
  
  /// Suspicious pattern thresholds
  static const int GRID_PATTERN_THRESHOLD = 3;
  static const double PERFECT_CIRCLE_THRESHOLD = 0.95;
  
  /// Analyze location for fraud patterns
  static Future<FraudAnalysis> analyzeLocation({
    required String userId,
    required Position currentPosition,
    required String tokenId,
  }) async {
    final issues = <String>[];
    double fraudScore = 0.0;
    
    try {
      // 1. Check velocity from last location
      final velocityCheck = await _checkVelocity(userId, currentPosition);
      if (velocityCheck.isImpossible) {
        issues.add('Impossible travel speed: ${velocityCheck.speed.toStringAsFixed(0)} km/h');
        fraudScore += 0.5;
        print('🚫 FRAUD: Teleportation detected - ${velocityCheck.speed} km/h');
      }
      
      // 2. Check for grid patterns (common in spoofing)
      final gridCheck = await _checkGridPattern(userId, currentPosition);
      if (gridCheck.isGrid) {
        issues.add('Suspicious grid pattern in location history');
        fraudScore += 0.3;
        print('⚠️ FRAUD: Grid pattern detected');
      }
      
      // 3. Check for perfect circles (joystick spoofing)
      final circleCheck = await _checkCircularPattern(userId, currentPosition);
      if (circleCheck.isCircular) {
        issues.add('Circular movement pattern (joystick spoofing)');
        fraudScore += 0.4;
        print('⚠️ FRAUD: Circular/joystick pattern detected');
      }
      
      // 4. Check for location clustering (jumping between saved locations)
      final clusterCheck = await _checkLocationClustering(userId, currentPosition);
      if (clusterCheck.isSuspicious) {
        issues.add('Jumping between fixed locations');
        fraudScore += 0.3;
        print('⚠️ FRAUD: Location clustering detected');
      }
      
      // 5. Check for time anomalies
      final timeCheck = await _checkTimeAnomalies(userId, currentPosition);
      if (timeCheck.hasAnomaly) {
        issues.add('Time sequence anomaly detected');
        fraudScore += 0.4;
        print('⚠️ FRAUD: Time anomaly - ${timeCheck.description}');
      }
      
      // 6. Check country hopping
      final countryCheck = await _checkCountryHopping(userId, currentPosition);
      if (countryCheck.isSuspicious) {
        issues.add('Rapid country changes detected');
        fraudScore += 0.5;
        print('🚫 FRAUD: Country hopping detected');
      }
      
      // 7. Check for known VPN exit points
      final vpnExitCheck = await _checkVPNExitPoints(currentPosition);
      if (vpnExitCheck.isVPNExit) {
        issues.add('Location matches known VPN exit point');
        fraudScore += 0.3;
        print('⚠️ FRAUD: VPN exit point location');
      }
      
      // 8. Statistical anomaly detection
      final statsCheck = await _checkStatisticalAnomalies(userId, currentPosition);
      if (statsCheck.isAnomaly) {
        issues.add('Statistical anomaly in movement pattern');
        fraudScore += 0.2;
        print('⚠️ FRAUD: Statistical anomaly detected');
      }
      
    } catch (e) {
      print('Fraud detection error: $e');
    }
    
    // Calculate final fraud probability
    final fraudProbability = math.min(fraudScore, 1.0);
    final isFraudulent = fraudProbability > 0.7;
    
    return FraudAnalysis(
      isFraudulent: isFraudulent,
      fraudProbability: fraudProbability,
      issues: issues,
    );
  }
  
  /// Check velocity from last known location
  static Future<VelocityCheck> _checkVelocity(String userId, Position current) async {
    try {
      // Get last location for this user
      final lastTrade = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      
      if (lastTrade.docs.isEmpty) {
        return VelocityCheck(isImpossible: false, speed: 0);
      }
      
      final lastData = lastTrade.docs.first.data();
      final lastLocation = lastData['location'];
      final lastTimestamp = (lastData['timestamp'] as Timestamp).toDate();
      
      // Calculate distance and time
      final distance = _calculateDistance(
        lastLocation['latitude'],
        lastLocation['longitude'],
        current.latitude,
        current.longitude,
      );
      
      final timeDiff = DateTime.now().difference(lastTimestamp).inHours;
      if (timeDiff == 0) return VelocityCheck(isImpossible: false, speed: 0);
      
      final speed = distance / timeDiff; // km/h
      
      return VelocityCheck(
        isImpossible: speed > MAX_REALISTIC_SPEED,
        speed: speed,
      );
    } catch (e) {
      return VelocityCheck(isImpossible: false, speed: 0);
    }
  }
  
  /// Check for grid patterns in location history
  static Future<GridCheck> _checkGridPattern(String userId, Position current) async {
    try {
      // Get last 10 locations
      final trades = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      
      if (trades.docs.length < 5) {
        return GridCheck(isGrid: false);
      }
      
      // Check if locations align on a grid (common in spoofing apps)
      int alignedCount = 0;
      for (var doc in trades.docs) {
        final loc = doc.data()['location'];
        final lat = loc['latitude'] as double;
        final lng = loc['longitude'] as double;
        
        // Check if coordinates are suspiciously round
        if (_isRoundCoordinate(lat) || _isRoundCoordinate(lng)) {
          alignedCount++;
        }
      }
      
      return GridCheck(isGrid: alignedCount >= GRID_PATTERN_THRESHOLD);
    } catch (e) {
      return GridCheck(isGrid: false);
    }
  }
  
  /// Check for circular patterns (joystick movement)
  static Future<CircleCheck> _checkCircularPattern(String userId, Position current) async {
    try {
      // Get last 20 locations
      final trades = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      
      if (trades.docs.length < 10) {
        return CircleCheck(isCircular: false);
      }
      
      // Calculate center point
      double avgLat = 0, avgLng = 0;
      for (var doc in trades.docs) {
        final loc = doc.data()['location'];
        avgLat += loc['latitude'];
        avgLng += loc['longitude'];
      }
      avgLat /= trades.docs.length;
      avgLng /= trades.docs.length;
      
      // Check if all points are roughly equidistant from center
      final distances = <double>[];
      for (var doc in trades.docs) {
        final loc = doc.data()['location'];
        final dist = _calculateDistance(
          avgLat, avgLng,
          loc['latitude'], loc['longitude'],
        );
        distances.add(dist);
      }
      
      // Calculate standard deviation
      final avgDist = distances.reduce((a, b) => a + b) / distances.length;
      final variance = distances.map((d) => math.pow(d - avgDist, 2)).reduce((a, b) => a + b) / distances.length;
      final stdDev = math.sqrt(variance);
      
      // Low standard deviation means circular pattern
      final coefficient = stdDev / avgDist;
      
      return CircleCheck(isCircular: coefficient < (1 - PERFECT_CIRCLE_THRESHOLD));
    } catch (e) {
      return CircleCheck(isCircular: false);
    }
  }
  
  /// Check for location clustering (saved locations)
  static Future<ClusterCheck> _checkLocationClustering(String userId, Position current) async {
    try {
      // Get all historical locations
      final trades = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      
      if (trades.docs.length < 10) {
        return ClusterCheck(isSuspicious: false);
      }
      
      // Group locations into clusters
      final clusters = <List<Map<String, dynamic>>>[];
      for (var doc in trades.docs) {
        final loc = doc.data()['location'];
        bool addedToCluster = false;
        
        for (var cluster in clusters) {
          final clusterCenter = cluster.first;
          final dist = _calculateDistance(
            clusterCenter['latitude'], clusterCenter['longitude'],
            loc['latitude'], loc['longitude'],
          );
          
          if (dist < 0.1) { // Within 100 meters
            cluster.add(loc);
            addedToCluster = true;
            break;
          }
        }
        
        if (!addedToCluster) {
          clusters.add([loc]);
        }
      }
      
      // Suspicious if jumping between few fixed locations
      final clusterRatio = clusters.length / trades.docs.length;
      return ClusterCheck(isSuspicious: clusterRatio < 0.3 && clusters.length < 5);
    } catch (e) {
      return ClusterCheck(isSuspicious: false);
    }
  }
  
  /// Check for time anomalies
  static Future<TimeCheck> _checkTimeAnomalies(String userId, Position current) async {
    try {
      // Check if timestamps are regular intervals (bot behavior)
      final trades = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      
      if (trades.docs.length < 5) {
        return TimeCheck(hasAnomaly: false, description: '');
      }
      
      final intervals = <int>[];
      for (int i = 0; i < trades.docs.length - 1; i++) {
        final t1 = (trades.docs[i].data()['timestamp'] as Timestamp).millisecondsSinceEpoch;
        final t2 = (trades.docs[i + 1].data()['timestamp'] as Timestamp).millisecondsSinceEpoch;
        intervals.add((t1 - t2).abs());
      }
      
      // Check if intervals are suspiciously regular
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals.map((i) => math.pow(i - avgInterval, 2)).reduce((a, b) => a + b) / intervals.length;
      final stdDev = math.sqrt(variance);
      
      // Very low standard deviation means bot-like behavior
      if (stdDev < avgInterval * 0.1) {
        return TimeCheck(hasAnomaly: true, description: 'Regular interval pattern (bot-like)');
      }
      
      return TimeCheck(hasAnomaly: false, description: '');
    } catch (e) {
      return TimeCheck(hasAnomaly: false, description: '');
    }
  }
  
  /// Check for rapid country changes
  static Future<CountryCheck> _checkCountryHopping(String userId, Position current) async {
    // Would use reverse geocoding to determine countries
    // For now, simplified check based on large distance changes
    
    try {
      final trades = await _firestore
          .collection('trades')
          .where('to_user', isEqualTo: userId)
          .where('location', isNotEqualTo: null)
          .orderBy('location')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();
      
      int countryChanges = 0;
      for (var doc in trades.docs) {
        final loc = doc.data()['location'];
        final dist = _calculateDistance(
          loc['latitude'], loc['longitude'],
          current.latitude, current.longitude,
        );
        
        // If distance > 1000km, likely different country
        if (dist > 1000) {
          countryChanges++;
        }
      }
      
      return CountryCheck(isSuspicious: countryChanges > 2);
    } catch (e) {
      return CountryCheck(isSuspicious: false);
    }
  }
  
  /// Check if location matches known VPN exit points
  static Future<VPNExitCheck> _checkVPNExitPoints(Position current) async {
    // Known VPN datacenter locations (simplified list)
    final vpnExitPoints = [
      {'lat': 52.3702, 'lng': 4.8952, 'name': 'Amsterdam DC'},
      {'lat': 51.5074, 'lng': -0.1278, 'name': 'London DC'},
      {'lat': 40.7128, 'lng': -74.0060, 'name': 'NYC DC'},
      {'lat': 37.7749, 'lng': -122.4194, 'name': 'SF DC'},
      {'lat': 35.6762, 'lng': 139.6503, 'name': 'Tokyo DC'},
      // Add more datacenter locations
    ];
    
    for (var point in vpnExitPoints) {
      final dist = _calculateDistance(
        point['lat'] as double,
        point['lng'] as double,
        current.latitude,
        current.longitude,
      );
      
      if (dist < 5) { // Within 5km of datacenter
        print('⚠️ Location near VPN exit: ${point['name']}');
        return VPNExitCheck(isVPNExit: true);
      }
    }
    
    return VPNExitCheck(isVPNExit: false);
  }
  
  /// Statistical anomaly detection
  static Future<StatsCheck> _checkStatisticalAnomalies(String userId, Position current) async {
    // Implement statistical analysis of movement patterns
    // Using standard deviation, outlier detection, etc.
    return StatsCheck(isAnomaly: false);
  }
  
  /// Helper: Calculate distance between coordinates
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
  
  static double _toRadians(double degree) => degree * (math.pi / 180);
  
  /// Check if coordinate is suspiciously round
  static bool _isRoundCoordinate(double coord) {
    final fractional = coord - coord.truncate();
    // Check if fractional part is 0, 0.5, 0.25, etc.
    return fractional == 0 || 
           fractional == 0.5 || 
           fractional == 0.25 || 
           fractional == 0.75;
  }
}

/// Fraud analysis result
class FraudAnalysis {
  final bool isFraudulent;
  final double fraudProbability;
  final List<String> issues;
  
  FraudAnalysis({
    required this.isFraudulent,
    required this.fraudProbability,
    required this.issues,
  });
}

// Check result classes
class VelocityCheck {
  final bool isImpossible;
  final double speed;
  VelocityCheck({required this.isImpossible, required this.speed});
}

class GridCheck {
  final bool isGrid;
  GridCheck({required this.isGrid});
}

class CircleCheck {
  final bool isCircular;
  CircleCheck({required this.isCircular});
}

class ClusterCheck {
  final bool isSuspicious;
  ClusterCheck({required this.isSuspicious});
}

class TimeCheck {
  final bool hasAnomaly;
  final String description;
  TimeCheck({required this.hasAnomaly, required this.description});
}

class CountryCheck {
  final bool isSuspicious;
  CountryCheck({required this.isSuspicious});
}

class VPNExitCheck {
  final bool isVPNExit;
  VPNExitCheck({required this.isVPNExit});
}

class StatsCheck {
  final bool isAnomaly;
  StatsCheck({required this.isAnomaly});
} 