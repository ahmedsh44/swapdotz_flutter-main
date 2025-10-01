/// Flutter Integration Guide for SwapDotz Firebase Backend
/// 
/// This file shows how to integrate the Firebase Cloud Functions
/// with your Flutter NFC app.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SwapDotzFirebaseService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  }) async {
    try {
      final callable = _functions.httpsCallable('registerToken');
      final result = await callable.call({
        'token_uid': tokenUid,
        'key_hash': keyHash,
        'metadata': metadata ?? {},
      });
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Initiate a transfer session
  static Future<InitiateTransferResponse> initiateTransfer({
    required String tokenUid,
    String? toUserId,
    int? sessionDurationMinutes,
  }) async {
    try {
      final callable = _functions.httpsCallable('initiateTransfer');
      final result = await callable.call({
        'token_uid': tokenUid,
        'to_user_id': toUserId,
        'session_duration_minutes': sessionDurationMinutes ?? 5,
      });
      
      return InitiateTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Complete a transfer
  /// Stage a transfer (Phase 1 of two-phase commit) - NEW RECOMMENDED APPROACH
  static Future<StageTransferResponse> stageTransfer({
    required String sessionId,
    String? challengeResponse,
    required String newKeyHash,
  }) async {
    try {
      final callable = _functions.httpsCallable('stageTransfer');
      final result = await callable.call({
        'session_id': sessionId,
        'challenge_response': challengeResponse,
        'new_key_hash': newKeyHash,
      });
      
      return StageTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Commit a staged transfer (Phase 2 of two-phase commit)
  static Future<CompleteTransferResponse> commitTransfer({
    required String stagedTransferId,
  }) async {
    try {
      final callable = _functions.httpsCallable('commitTransfer');
      final result = await callable.call({
        'staged_transfer_id': stagedTransferId,
      });
      
      return CompleteTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  /// Rollback a staged transfer when NFC write fails
  static Future<RollbackTransferResponse> rollbackTransfer({
    required String stagedTransferId,
    String? reason,
  }) async {
    try {
      final callable = _functions.httpsCallable('rollbackTransfer');
      final result = await callable.call({
        'staged_transfer_id': stagedTransferId,
        'reason': reason ?? 'NFC write failed',
      });
      
      return RollbackTransferResponse.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      print('Firebase function error: ${e.code} - ${e.message}');
      throw e;
    }
  }

  static Future<CompleteTransferResponse> completeTransfer({
    required String sessionId,
    String? challengeResponse,
    required String newKeyHash,
  }) async {
    try {
      final callable = _functions.httpsCallable('completeTransfer');
      final result = await callable.call({
        'session_id': sessionId,
        'challenge_response': challengeResponse,
        'new_key_hash': newKeyHash,
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
  static Future<TransferSession?> getTransferSession(String sessionId) async {
    try {
      final doc = await _firestore
          .collection('transfer_sessions')
          .doc(sessionId)
          .get();
      
      if (!doc.exists) return null;
      return TransferSession.fromFirestore(doc);
    } catch (e) {
      print('Error fetching transfer session: $e');
      return null;
    }
  }

  /// Get user's owned tokens
  static Stream<List<Token>> getUserTokens(String userId) {
    return _firestore
        .collection('tokens')
        .where('current_owner_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Token.fromFirestore(doc))
          .toList();
    });
  }

  /// Queue a server command for a specific token (Admin only)
  Future<void> queueServerCommand(String tokenUid, Map<String, dynamic> command) async {
    try {
      final result = await _functions.httpsCallable('queueServerCommand').call({
        'token_uid': tokenUid,
        'command': command,
      });
      
      print('Server command queued: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to queue command: ${e.message}');
    }
  }
  
  /// Example: Queue an encryption upgrade for a specific token
  Future<void> upgradeTokenEncryption(String tokenUid) async {
    await queueServerCommand(tokenUid, {
      'type': 'upgrade_des_to_aes',
      'priority': 'high',
      'params': {
        'backup_data': true,
      }
    });
  }
  
  /// Example: Emergency lockdown of a compromised token
  Future<void> emergencyLockdownToken(String tokenUid, String reason) async {
    await queueServerCommand(tokenUid, {
      'type': 'emergency_lockdown',
      'priority': 'critical',
      'params': {
        'reason': reason,
      }
    });
  }
  
  /// Batch upgrade all DES tokens to AES (Admin only)
  Future<void> batchUpgradeAllTokens() async {
    try {
      final result = await _functions.httpsCallable('batchUpgradeEncryption').call();
      print('Batch upgrade initiated: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to initiate batch upgrade: ${e.message}');
    }
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

class StageTransferResponse {
  final bool success;
  final String stagedTransferId;
  final String newOwnerId;

  StageTransferResponse({
    required this.success,
    required this.stagedTransferId,
    required this.newOwnerId,
  });

  factory StageTransferResponse.fromMap(Map<String, dynamic> data) {
    return StageTransferResponse(
      success: data['success'],
      stagedTransferId: data['staged_transfer_id'],
      newOwnerId: data['new_owner_id'],
    );
  }
}

class RollbackTransferResponse {
  final bool success;
  final String message;

  RollbackTransferResponse({
    required this.success,
    required this.message,
  });

  factory RollbackTransferResponse.fromMap(Map<String, dynamic> data) {
    return RollbackTransferResponse(
      success: data['success'],
      message: data['message'],
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
    return Token(
      uid: data['uid'],
      currentOwnerId: data['current_owner_id'],
      previousOwners: List<String>.from(data['previous_owners']),
      keyHash: data['key_hash'],
      createdAt: (data['created_at'] as Timestamp).toDate(),
      lastTransferAt: (data['last_transfer_at'] as Timestamp).toDate(),
      metadata: TokenMetadata.fromMap(data['metadata']),
    );
  }
}

class TokenMetadata {
  final Map<String, dynamic> travelStats;
  final int leaderboardPoints;
  final Map<String, dynamic>? customAttributes;
  final String? series;
  final String? edition;
  final String? rarity;

  TokenMetadata({
    required this.travelStats,
    required this.leaderboardPoints,
    this.customAttributes,
    this.series,
    this.edition,
    this.rarity,
  });

  factory TokenMetadata.fromMap(Map<String, dynamic> data) {
    return TokenMetadata(
      travelStats: data['travel_stats'] ?? {},
      leaderboardPoints: data['leaderboard_points'] ?? 0,
      customAttributes: data['custom_attributes'],
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

  TransferSession({
    required this.sessionId,
    required this.tokenUid,
    required this.fromUserId,
    this.toUserId,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
  });

  factory TransferSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransferSession(
      sessionId: data['session_id'],
      tokenUid: data['token_uid'],
      fromUserId: data['from_user_id'],
      toUserId: data['to_user_id'],
      expiresAt: (data['expires_at'] as Timestamp).toDate(),
      status: data['status'],
      createdAt: (data['created_at'] as Timestamp).toDate(),
    );
  }
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
/// // 4a. NEW RECOMMENDED APPROACH: Two-phase commit with rollback support
/// try {
///   // Stage the transfer (Phase 1)
///   final staged = await SwapDotzFirebaseService.stageTransfer(
///     sessionId: transfer.sessionId,
///     challengeResponse: 'response_to_challenge',
///     newKeyHash: 'new_hashed_key_after_rekey',
///   );
///   
///   // Perform NFC write operations here
///   // If NFC write fails, call rollback:
///   try {
///     await performNFCWrite(newKey);
///     
///     // If NFC write succeeds, commit the transfer (Phase 2)
///     final completion = await SwapDotzFirebaseService.commitTransfer(
///       stagedTransferId: staged.stagedTransferId,
///     );
///   } catch (nfcError) {
///     // NFC write failed - rollback the swapdot and hash changes
///     await SwapDotzFirebaseService.rollbackTransfer(
///       stagedTransferId: staged.stagedTransferId,
///       reason: 'NFC write failed: ${nfcError.toString()}',
///     );
///     throw nfcError; // Re-throw for handling
///   }
/// } catch (e) {
///   print('Transfer failed: $e');
/// }
/// 
/// // 4b. LEGACY APPROACH: Direct completion (no rollback support)
/// final completion = await SwapDotzFirebaseService.completeTransfer(
///   sessionId: transfer.sessionId,
///   challengeResponse: 'response_to_challenge',
///   newKeyHash: 'new_hashed_key_after_rekey',
/// );
/// ``` 