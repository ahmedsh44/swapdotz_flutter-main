/// Flutter Integration Guide for SwapDotz Firebase Backend
/// 
/// This file shows how to integrate the Firebase Cloud Functions
/// with your Flutter NFC app.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'network_security_service.dart';
import 'anti_spoofing_service.dart';
import 'dart:math';
import 'dart:convert';

class SwapDotzFirebaseService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ensure there is an authenticated Firebase user (anonymous if needed)
  static Future<User> ensureAuth() async {
    final user = _auth.currentUser;
    if (user != null) return user;
    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  /// Get a custom token for the given test UID from backend and sign in
  static Future<User> signInAsTestUser(String uid) async {
    final callable = _functions.httpsCallable('getTestCustomToken');
    final res = await callable.call({ 'uid': uid });
    final token = (res.data as Map)['token'] as String;
    final cred = await _auth.signInWithCustomToken(token);
    return cred.user!;
  }

  /// Switch to a logical test user by name (e.g., 'gifter' or 'receiver')
  static Future<User> switchToNamedUser(String name) async {
    // Map logical names to stable UIDs
    final uid = name.toLowerCase();
    return signInAsTestUser(uid);
  }

  /// Get current GPS location as Position object (for pre-loading)
  static Future<Position?> getCurrentPositionObject() async {
    try {
      print('🌍 Getting current location (Position object)...');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('🔧 Location services enabled: $serviceEnabled');
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        throw Exception('Location services are disabled. Please enable GPS/Location in your device settings.');
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      print('🔐 Current permission status: $permission');
      
      // Additional debugging
      final locationSettings = LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      );
      print('🔧 Location settings: accuracy=${locationSettings.accuracy}, distanceFilter=${locationSettings.distanceFilter}');
      
      if (permission == LocationPermission.denied) {
        print('🔐 Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          throw Exception('Location permissions are denied. Please grant location access to register tokens.');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        throw Exception('Location permissions are permanently denied. Please enable location access in app settings.');
      }

      // Try to get current position, fallback to last known location
      print('📍 Getting position...');
      Position? position;
      
      try {
        print('🔧 Attempting getCurrentPosition with LOW accuracy (network/wifi) first...');
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low, // Use network/wifi first (like Google Maps)
          timeLimit: const Duration(seconds: 5), // Short timeout for network location
        );
        print('✅ Network location obtained: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('⚠️ Network location failed: $e');
        print('🔧 Trying last known location immediately (Google Maps style)...');
        
        try {
          position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            print('✅ Last known location obtained: ${position.latitude}, ${position.longitude}');
            print('📅 Location age: ${DateTime.now().difference(position.timestamp!).inMinutes} minutes old');
          } else {
            print('⚠️ No last known location available');
          }
        } catch (lastKnownError) {
          print('⚠️ Last known location failed: $lastKnownError');
        }
      }
      
      // If we still don't have a position, fail gracefully
      if (position == null) {
        print('❌ Unable to obtain any location (network, GPS, or cached)');
        throw Exception('Location unavailable. Please ensure location services are enabled and try again.');
      }
      
      print('✅ Position object obtained: ${position.latitude}, ${position.longitude}');
      print('📍 Accuracy: ${position.accuracy}m');
      
      return position;
    } catch (e) {
      print('❌ Error getting position: $e');
      return null;
    }
  }

  /// Get current GPS location with proper permission handling
  static Future<Map<String, dynamic>?> getCurrentLocation() async {
    try {
      print('🌍 Getting current location...');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('🔧 Location services enabled: $serviceEnabled');
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        throw Exception('Location services are disabled. Please enable GPS/Location in your device settings.');
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      print('🔐 Current permission status: $permission');
      
      // Additional debugging
      final locationSettings = LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      );
      print('🔧 Location settings: accuracy=${locationSettings.accuracy}, distanceFilter=${locationSettings.distanceFilter}');
      
      if (permission == LocationPermission.denied) {
        print('🔐 Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          throw Exception('Location permissions are denied. Please grant location access to register tokens.');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        throw Exception('Location permissions are permanently denied. Please enable location access in app settings.');
      }

      // Try to get current position, fallback to last known location
      print('📍 Getting position...');
      Position? position;
      
      try {
        print('🔧 Attempting getCurrentPosition with LOW accuracy (network/wifi) first...');
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low, // Use network/wifi first (like Google Maps)
          timeLimit: const Duration(seconds: 5), // Short timeout for network location
        );
        print('✅ Network location obtained: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('⚠️ Network location failed: $e');
        print('🔧 Trying last known location immediately (Google Maps style)...');
        
        try {
          position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            print('✅ Last known location obtained: ${position.latitude}, ${position.longitude}');
            print('📅 Location age: ${DateTime.now().difference(position.timestamp!).inMinutes} minutes old');
          } else {
            print('⚠️ No last known location available');
          }
                 } catch (lastKnownError) {
           print('⚠️ Last known location failed: $lastKnownError');
         }
      }
      
      // If we still don't have a position, fail gracefully
      if (position == null) {
        print('❌ Unable to obtain any location (network, GPS, or cached)');
        throw Exception('Location unavailable. Please ensure location services are enabled and try again.');
      }
      
      final location = {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp?.toIso8601String(),
        'source': position.timestamp != null && 
                 DateTime.now().difference(position.timestamp!).inMinutes < 5 
                 ? 'current' : 'fallback',
      };
      
      print('✅ Location obtained: ${position.latitude}, ${position.longitude}');
      print('📍 Accuracy: ${position.accuracy}m');
      
      return location;
    } catch (e) {
      print('❌ Error getting location: $e');
      return null;
    }
  }

  /// Authenticate the user anonymously
  static Future<User?> authenticateAnonymously() async {
    try {
      final credential = await _auth.signInAnonymously();
      return credential.user;
    } catch (e) {
      print('Authentication error: $e');
      return null;
    }
  }

  /// Register a new token when first scanned
  static Future<Map<String, dynamic>> registerToken({
    required String tokenUid,
    required String keyHash,
    Map<String, dynamic>? metadata,
    bool forceOverwrite = false,
    Position? gpsLocation,
  }) async {
    print('🔥 FIREBASE: registerToken() called');
    print('🔥   - Token UID: $tokenUid');
    print('🔥   - Key Hash: ${keyHash.substring(0, 16)}...');
    print('🔥   - Metadata: $metadata');
    
    try {
      final startTime = DateTime.now();
      
      // Use provided GPS location or get current location
      Map<String, dynamic> location;
      if (gpsLocation != null) {
        print('🔥   - Using pre-obtained GPS location...');
        location = {
          'lat': gpsLocation.latitude,
          'lng': gpsLocation.longitude,
          'accuracy': gpsLocation.accuracy,
          'timestamp': gpsLocation.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'source': 'preloaded',
        };
        print('🔥   - Location: ${location['lat']}, ${location['lng']} (accuracy: ${location['accuracy']}m)');
      } else {
        print('🔥   - Getting GPS location...');
        final gpsResult = await getCurrentLocation();
        if (gpsResult == null) {
          throw Exception('Failed to get GPS location. Please enable location services and grant location permissions.');
        }
        location = gpsResult;
        print('🔥   - Location obtained: ${location['lat']}, ${location['lng']}');
      }
      
      print('🔥   - Calling Cloud Function: registerToken');
      
      final callable = _functions.httpsCallable('registerToken');
      final payload = {
        'token_uid': tokenUid,
        'key_hash': keyHash,
        'metadata': metadata ?? {},
        'gps_location': location,
        'force_overwrite': forceOverwrite,
      };
      
      print('🔥   - Function payload: $payload');
      final result = await callable.call(payload);
      
      final duration = DateTime.now().difference(startTime);
      print('🔥   - Function completed in ${duration.inMilliseconds}ms');
      print('🔥   - RESULT: ${result.data}');
      
      return result.data;
    } on FirebaseFunctionsException catch (e, stackTrace) {
      print('🔥   - ERROR: Firebase function failed');
      print('🔥   - Code: ${e.code}');
      print('🔥   - Message: ${e.message}');
      print('🔥   - Details: ${e.details}');
      print('🔥   - Stack trace: $stackTrace');
      throw e;
    } catch (e, stackTrace) {
      print('🔥   - ERROR: Unexpected error in registerToken');
      print('🔥   - Error: $e');
      print('🔥   - Stack trace: $stackTrace');
      throw e;
    }
  }

  /// Initiate a transfer session
  static Future<InitiateTransferResponse> initiateTransfer({
    required String tokenUid,
    String? toUserId,
    int? sessionDurationMinutes,
    Position? gpsLocation,
  }) async {
    try {
      // Use preloaded GPS or fetch now
      Map<String, dynamic> location;
      if (gpsLocation != null) {
        print('🔥 INITIATE: Using preloaded GPS');
        location = {
          'lat': gpsLocation.latitude,
          'lng': gpsLocation.longitude,
          'accuracy': gpsLocation.accuracy,
          'timestamp': gpsLocation.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'source': 'preloaded',
        };
      } else {
        print('🔥 INITIATE: Getting GPS location...');
        final loc = await getCurrentLocation();
        if (loc == null) {
          throw Exception('Failed to get GPS location. Please enable location services and grant location permissions.');
        }
        location = loc;
      }
      print('🔥 INITIATE: Location: ${location['lat']}, ${location['lng']}');
      
      final callable = _functions.httpsCallable('initiateTransfer');
      final result = await callable.call({
        'token_uid': tokenUid,
        'to_user_id': toUserId,
        'session_duration_minutes': sessionDurationMinutes ?? 2,
        'gps_location': location,
        'request_nonce': _generateRequestNonce(),
        'request_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      return InitiateTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Complete a transfer
  static Future<CompleteTransferResponse> completeTransfer({
    required String sessionId,
    String? challengeResponse,
    required String newKeyHash,
    String? newOwnerId,
    Position? gpsLocation,
  }) async {
    try {
      // Use preloaded GPS or fetch now
      Map<String, dynamic> location;
      if (gpsLocation != null) {
        print('🔥 COMPLETE: Using preloaded GPS');
        location = {
          'lat': gpsLocation.latitude,
          'lng': gpsLocation.longitude,
          'accuracy': gpsLocation.accuracy,
          'timestamp': gpsLocation.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
          'source': 'preloaded',
        };
      } else {
        print('🔥 COMPLETE: Getting GPS location...');
        final loc = await getCurrentLocation();
        if (loc == null) {
          throw Exception('Failed to get GPS location. Please enable location services and grant location permissions.');
        }
        location = loc;
      }
      print('🔥 COMPLETE: Location: ${location['lat']}, ${location['lng']}');
      
      final callable = _functions.httpsCallable('completeTransfer');
      final result = await callable.call({
        'session_id': sessionId,
        'challenge_response': challengeResponse,
        'new_key_hash': newKeyHash,
        'new_owner_id': newOwnerId,
        'gps_location': location,
      });
      
      return CompleteTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Validate a challenge response
  static Future<bool> validateChallenge({
    required String sessionId,
    required String challengeResponse,
  }) async {
    try {
      final callable = _functions.httpsCallable('validateChallenge');
      final result = await callable.call({
        'session_id': sessionId,
        'challenge_response': challengeResponse,
      });
      
      return result.data['valid'] ?? false;
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Listen to real-time token updates
  static Stream<Token?> watchToken(String tokenUid) {
    return _firestore
        .collection('tokens')
        .doc(tokenUid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return null;
      return Token.fromFirestore(snapshot);
    });
  }

  /// Get transfer session details
  /// ALWAYS fetches fresh data from server for security
  static Future<TransferSession?> getTransferSession(String sessionId) async {
    try {
      // CRITICAL: Force fresh read from server
      final doc = await _firestore
          .collection('transfer_sessions')
          .doc(sessionId)
          .get(const GetOptions(source: Source.server));
      
      print('🔄 Transfer session check: ${doc.exists ? "EXISTS" : "NOT FOUND"}');
      if (!doc.exists) return null;
      return TransferSession.fromFirestore(doc);
    } catch (e) {
      print('Error fetching transfer session from server: $e');
      // Fallback to cache if offline
      if (e.toString().contains('unavailable')) {
        try {
          final cachedDoc = await _firestore
              .collection('transfer_sessions')
              .doc(sessionId)
              .get(const GetOptions(source: Source.cache));
          if (cachedDoc.exists) {
            print('⚠️ WARNING: Using CACHED transfer session - may be stale!');
            return TransferSession.fromFirestore(cachedDoc);
          }
        } catch (_) {}
      }
      return null;
    }
  }

  /// Get user's owned tokens
  static Stream<List<Token>> getUserTokens(String userId) {
    print('🔍 getUserTokens: Fetching tokens for userId: $userId');
    
    // Try both fields with proper error handling
    // Start with current_owner_id which should have an index
    return _firestore
        .collection('tokens')
        .where('current_owner_id', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      print('🔍 getUserTokens: Query 1 - Found ${snapshot.docs.length} tokens with current_owner_id=$userId');
      
      final tokenIds = <String>{};
      final allTokens = <Token>[];
      
      // Add tokens from current_owner_id query
      for (final doc in snapshot.docs) {
        if (!tokenIds.contains(doc.id)) {
          tokenIds.add(doc.id);
          final token = Token.fromFirestore(doc);
          print('🔍 getUserTokens: Token ${doc.id} - owner: ${token.currentOwnerId}');
          allTokens.add(token);
        }
      }
      
      // Try to also check ownerUid if it exists (might not have index)
      try {
        final ownerUidQuery = await _firestore
            .collection('tokens')
            .where('ownerUid', isEqualTo: userId)
            .get();
        
        print('🔍 getUserTokens: Query 2 - Found ${ownerUidQuery.docs.length} tokens with ownerUid=$userId');
        
        // Add tokens from ownerUid query that aren't already included
        for (final doc in ownerUidQuery.docs) {
          if (!tokenIds.contains(doc.id)) {
            tokenIds.add(doc.id);
            final token = Token.fromFirestore(doc);
            print('🔍 getUserTokens: Additional token ${doc.id} - owner: ${token.currentOwnerId}');
            allTokens.add(token);
          }
        }
      } catch (e) {
        print('🔍 getUserTokens: Could not query ownerUid field (might need index): $e');
        // Continue with just current_owner_id results
      }
      
      print('🔍 getUserTokens: Returning ${allTokens.length} total unique tokens for user $userId');
      return allTokens;
    }).handleError((error) {
      print('❌ getUserTokens ERROR: $error');
      // Return empty list on error
      return <Token>[];
    });
  }

  /// Get a specific token by ID
  /// ALWAYS fetches fresh data from server for security
  static Future<Token?> getToken(String tokenUid) async {
    print('🔥 FIREBASE: getToken() called');
    print('🔥   - Token UID: $tokenUid');
    print('🔥   - Collection: tokens');
    print('🔥   - Forcing FRESH read from server (not cache)');
    
    try {
      final startTime = DateTime.now();
      print('🔥   - Starting Firestore read operation...');
      
      // CRITICAL: Always fetch fresh data from server for ownership checks
      final doc = await _firestore
          .collection('tokens')
          .doc(tokenUid)
          .get(const GetOptions(source: Source.server));
      
      final duration = DateTime.now().difference(startTime);
      print('🔥   - Firestore read completed in ${duration.inMilliseconds}ms');
      print('🔥   - Document exists: ${doc.exists}');
      
      if (!doc.exists) {
        print('🔥   - RESULT: Token not found in Firebase');
        return null;
      }
      
      final data = doc.data() as Map<String, dynamic>;
      print('🔥   - Document data keys: ${data.keys.toList()}');
      print('🔥   - Raw ownerUid field: ${data['ownerUid']}');
      print('🔥   - Raw current_owner_id field: ${data['current_owner_id']}');
      print('🔥   - Key hash preview: ${data['key_hash']?.substring(0, 16)}...');
      
      final token = Token.fromFirestore(doc);
      print('🔥   - PARSED Token owner (currentOwnerId): ${token.currentOwnerId}');
      print('🔥   - RESULT: Token successfully parsed from Firestore');
      return token;
    } catch (e, stackTrace) {
      print('🔥   - ERROR: Failed to fetch token from server');
      print('🔥   - Error: $e');
      
      // If offline, try cache as fallback (but log a warning)
      if (e.toString().contains('unavailable') || e.toString().contains('offline')) {
        print('🔥   - Device appears offline, trying cache as fallback...');
        try {
          final cachedDoc = await _firestore
              .collection('tokens')
              .doc(tokenUid)
              .get(const GetOptions(source: Source.cache));
          
          if (cachedDoc.exists) {
            print('⚠️ WARNING: Using CACHED token data - may be stale!');
            print('⚠️ This should NOT be used for security decisions!');
            return Token.fromFirestore(cachedDoc);
          }
        } catch (cacheError) {
          print('🔥   - Cache also failed: $cacheError');
        }
      }
      
      print('🔥   - Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get current authenticated user ID
  static Future<String?> getCurrentUserId() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('🔐 getCurrentUserId: No current user, signing in anonymously');
      // Try to authenticate anonymously if not already authenticated
      final credential = await _auth.signInAnonymously();
      final newUserId = credential.user?.uid;
      print('🔐 getCurrentUserId: New anonymous user created: $newUserId');
      return newUserId;
    }
    print('🔐 getCurrentUserId: Returning existing user: ${user.uid}');
    return user.uid;
  }

  /// Get pending (and unexpired) transfer sessions for a token
  /// ALWAYS fetches fresh data from server for security
  static Future<List<TransferSession>> getPendingTransferSessions(String tokenUid) async {
    try {
      // CRITICAL: Force fresh read from server
      final snapshot = await _firestore
          .collection('transferSessions')  // Fixed: camelCase
          .where('token_uid', isEqualTo: tokenUid)
          .where('status', isEqualTo: 'pending')
          .get(const GetOptions(source: Source.server));

      print('🔄 Pending transfer sessions check: Found ${snapshot.docs.length} sessions');
      
      final now = DateTime.now();
      final sessions = snapshot.docs
          .map((doc) => TransferSession.fromFirestore(doc))
          .where((s) => s.expiresAt.isAfter(now))
          .toList();

      print('🔄 After filtering expired: ${sessions.length} active sessions');
      
      // Prefer the newest/longest remaining session first
      sessions.sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
      return sessions;
    } catch (e) {
      print('Error fetching pending transfer sessions from server: $e');
      // Fallback to cache if offline
      if (e.toString().contains('unavailable')) {
        try {
          final cachedSnapshot = await _firestore
              .collection('transfer_sessions')
              .where('token_uid', isEqualTo: tokenUid)
              .where('status', isEqualTo: 'pending')
              .get(const GetOptions(source: Source.cache));
          
          print('⚠️ WARNING: Using CACHED transfer sessions - may be stale!');
          
          final now = DateTime.now();
          final sessions = cachedSnapshot.docs
              .map((doc) => TransferSession.fromFirestore(doc))
              .where((s) => s.expiresAt.isAfter(now))
              .toList();
          
          sessions.sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
          return sessions;
        } catch (_) {}
      }
      return [];
    }
  }

  /// Stage a transfer (Phase 1)
  static Future<StagedTransferResult> stageTransfer({
    required String sessionId,
    String? challengeResponse,
    required String newKeyHash,
    String? newOwnerId,
  }) async {
    try {
      final callable = _functions.httpsCallable('stageTransfer');
      final result = await callable.call({
        'session_id': sessionId,
        'challenge_response': challengeResponse,
        'new_key_hash': newKeyHash,
        'new_owner_id': newOwnerId,
        'request_nonce': _generateRequestNonce(),
        'request_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final data = result.data as Map<String, dynamic>;
      return StagedTransferResult(
        success: data['success'] == true,
        stagedTransferId: data['staged_transfer_id'] as String,
        newOwnerId: data['new_owner_id'] as String,
      );
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Stage a transfer with SERVER-SIDE validation (Phase 1) - SECURE VERSION
  /// This uses server-authoritative challenge validation
  static Future<StagedTransferResult> stageTransferSecure({
    required String sessionId,
    required String newKeyHash,
    String? newOwnerId,
    bool serverValidated = true,
  }) async {
    try {
      final callable = _functions.httpsCallable('stageTransferSecure');
      final result = await callable.call({
        'session_id': sessionId,
        'new_key_hash': newKeyHash,
        'new_owner_id': newOwnerId,
        'server_validated': serverValidated,
        'request_nonce': _generateRequestNonce(),
        'request_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final data = result.data as Map<String, dynamic>;
      return StagedTransferResult(
        success: data['success'] == true,
        stagedTransferId: data['staged_transfer_id'] as String,
        newOwnerId: data['new_owner_id'] as String,
      );
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Commit a staged transfer (Phase 2)
  static Future<CompleteTransferResponse> commitTransfer({
    required String stagedTransferId,
  }) async {
    try {
      final callable = _functions.httpsCallable('commitTransfer');
      final result = await callable.call({
        'staged_transfer_id': stagedTransferId,
        'request_nonce': _generateRequestNonce(),
        'request_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return CompleteTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Rollback a staged transfer
  static Future<void> rollbackTransfer({
    required String stagedTransferId,
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('rollbackTransfer');
      await callable.call({
        'staged_transfer_id': stagedTransferId,
        'reason': reason ?? 'NFC write failed',
        'request_nonce': _generateRequestNonce(),
        'request_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Generate a cryptographically secure nonce for server-side replay protection
  static String _generateRequestNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}

// Data Models for Flutter

class InitiateTransferResponse {
  final String sessionId;
  final DateTime expiresAt;
  final String? challenge;

  InitiateTransferResponse({
    required this.sessionId,
    required this.expiresAt,
    this.challenge,
  });

  factory InitiateTransferResponse.fromMap(Map<String, dynamic> data) {
    return InitiateTransferResponse(
      sessionId: data['session_id'],
      expiresAt: DateTime.parse(data['expires_at']),
      challenge: data['challenge'],
    );
  }
}

class CompleteTransferResponse {
  final bool success;
  final String newOwnerId;
  final String transferLogId;

  CompleteTransferResponse({
    required this.success,
    required this.newOwnerId,
    required this.transferLogId,
  });

  factory CompleteTransferResponse.fromMap(Map<String, dynamic> data) {
    return CompleteTransferResponse(
      success: data['success'],
      newOwnerId: data['new_owner_id'],
      transferLogId: data['transfer_log_id'],
    );
  }
}

class Token {
  final String uid;
  final String currentOwnerId;
  final List<String> previousOwners;
  final String keyHash;
  final DateTime createdAt;
  final DateTime lastTransferAt;
  final TokenMetadata metadata;

  Token({
    required this.uid,
    required this.currentOwnerId,
    required this.previousOwners,
    required this.keyHash,
    required this.createdAt,
    required this.lastTransferAt,
    required this.metadata,
  });

  factory Token.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // SECURITY: Handle both new (ownerUid) and legacy (current_owner_id) ownership fields
    // Prefer ownerUid if it exists, fallback to current_owner_id for backward compatibility
    final ownerId = data['ownerUid'] ?? data['current_owner_id'];
    
    print('🔍 Token.fromFirestore: Reading ownership fields');
    print('🔍   - ownerUid: ${data['ownerUid']}');
    print('🔍   - current_owner_id: ${data['current_owner_id']}');
    print('🔍   - Using: $ownerId');
    
    return Token(
      uid: data['uid'],
      currentOwnerId: ownerId,
      previousOwners: List<String>.from(data['previous_owners'] ?? []),
      keyHash: data['key_hash'],
      createdAt: (data['created_at'] as Timestamp).toDate(),
      lastTransferAt: (data['last_transfer_at'] as Timestamp).toDate(),
      metadata: TokenMetadata.fromMap(data['metadata'] ?? {}),
    );
  }
}

class TokenMetadata {
  final Map<String, dynamic> travelStats;
  final int leaderboardPoints;
  final Map<String, dynamic>? customAttributes;
  final String? name;
  final String? series;
  final String? edition;
  final String? rarity;

  TokenMetadata({
    required this.travelStats,
    required this.leaderboardPoints,
    this.customAttributes,
    this.name,
    this.series,
    this.edition,
    this.rarity,
  });

  factory TokenMetadata.fromMap(Map<String, dynamic> data) {
    return TokenMetadata(
      travelStats: data['travel_stats'] ?? {},
      leaderboardPoints: data['leaderboard_points'] ?? 0,
      customAttributes: data['custom_attributes'],
      name: data['name'],
      series: data['series'],
      edition: data['edition'],
      rarity: data['rarity'],
    );
  }
}

class TransferSession {
  final String sessionId;
  final String tokenUid;
  final String fromUserId;
  final String? toUserId;
  final DateTime expiresAt;
  final String status;
  final DateTime createdAt;
  final String? challenge;

  TransferSession({
    required this.sessionId,
    required this.tokenUid,
    required this.fromUserId,
    this.toUserId,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
    this.challenge,
  });

  factory TransferSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final Map<String, dynamic>? challengeData =
        (data['challenge_data'] as Map<String, dynamic>?);
    return TransferSession(
      sessionId: data['session_id'],
      tokenUid: data['token_uid'],
      fromUserId: data['from_user_id'],
      toUserId: data['to_user_id'],
      expiresAt: (data['expires_at'] as Timestamp).toDate(),
      status: data['status'],
      createdAt: (data['created_at'] as Timestamp).toDate(),
      challenge: challengeData != null ? challengeData['challenge'] as String? : null,
    );
  }
}

class StagedTransferResult {
  final bool success;
  final String stagedTransferId;
  final String newOwnerId;

  StagedTransferResult({
    required this.success,
    required this.stagedTransferId,
    required this.newOwnerId,
  });
}

/// Example usage in your Flutter app:
/// 
/// ```dart
/// // 1. Authenticate user
/// final user = await SwapDotzFirebaseService.authenticateAnonymously();
/// 
/// // 2. Register a new token (first scan)
/// final result = await SwapDotzFirebaseService.registerToken(
///   tokenUid: 'ABC123DEF456',
///   keyHash: 'hashed_key_value',
///   metadata: {
///     'series': 'Genesis',
///     'edition': '001',
///     'rarity': 'legendary',
///   },
/// );
/// 
/// // 3. Initiate transfer (current owner)
/// final transfer = await SwapDotzFirebaseService.initiateTransfer(
///   tokenUid: 'ABC123DEF456',
///   toUserId: null, // Open transfer - anyone can claim
/// );
/// 
/// // 4. Complete transfer (new owner)
/// final completion = await SwapDotzFirebaseService.completeTransfer(
///   sessionId: transfer.sessionId,
///   challengeResponse: 'response_to_challenge',
///   newKeyHash: 'new_hashed_key_after_rekey',
/// );
/// ``` 