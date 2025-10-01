import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Example client forwarder for server-authoritative DESFire operations
/// This code demonstrates how the mobile app forwards opaque APDU frames
/// without handling any cryptographic operations locally
class DESFireForwarder {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  /// Begin authentication with a token
  /// Returns sessionId for subsequent operations
  Future<String> beginAuthentication({
    required String tokenId,
    required String userId,
  }) async {
    // Poll for NFC tag
    final tag = await FlutterNfcKit.poll(
      timeout: Duration(seconds: 10),
      iosMultipleTagMessage: 'Multiple tags found',
      iosAlertMessage: 'Hold your device near the SwapDot',
    );

    if (tag.type != NFCTagType.iso7816) {
      throw Exception('Invalid tag type');
    }

    try {
      // Call Firebase Function to begin auth
      final callable = _functions.httpsCallable('beginAuthenticate');
      final result = await callable.call({
        'tokenId': tokenId,
        'userId': userId,
      });

      final data = result.data as Map<String, dynamic>;
      final sessionId = data['sessionId'] as String;
      final apdus = List<String>.from(data['apdus']);
      final expect = data['expect'] as String?;

      // Forward first APDU to card
      final response = await _forwardApdu(apdus[0]);

      // Continue authentication
      await _continueAuthentication(sessionId, response);

      return sessionId;
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  /// Continue multi-frame authentication
  Future<void> _continueAuthentication(
    String sessionId,
    String firstResponse,
  ) async {
    String response = firstResponse;
    bool done = false;

    while (!done) {
      // Send response to Firebase Function
      final callable = _functions.httpsCallable('continueAuthenticate');
      final result = await callable.call({
        'sessionId': sessionId,
        'response': response,
        'idempotencyKey': _generateIdempotencyKey(),
      });

      final data = result.data as Map<String, dynamic>;
      done = data['done'] ?? false;

      if (!done) {
        // Forward next APDU
        final apdus = List<String>.from(data['apdus'] ?? []);
        if (apdus.isNotEmpty) {
          response = await _forwardApdu(apdus[0]);
        }
      }
    }
  }

  /// Change key on the card
  Future<bool> changeKey({
    required String sessionId,
    required String targetKey, // 'mid' or 'new'
  }) async {
    try {
      // Get change key APDUs from server
      final callable = _functions.httpsCallable('changeKey');
      final result = await callable.call({
        'sessionId': sessionId,
        'targetKey': targetKey,
      });

      final data = result.data as Map<String, dynamic>;
      final apdus = List<String>.from(data['apdus']);
      final verifyToken = data['verifyToken'] as String;

      // Forward all APDUs to card and collect responses
      final responses = <String>[];
      for (final apdu in apdus) {
        final response = await _forwardApdu(apdu);
        responses.add(response);
      }

      // Verify key change with server
      return await _confirmChangeKey(
        sessionId: sessionId,
        responses: responses,
        verifyToken: verifyToken,
      );
    } catch (e) {
      print('Change key failed: $e');
      return false;
    }
  }

  /// Confirm key change with server
  Future<bool> _confirmChangeKey({
    required String sessionId,
    required List<String> responses,
    required String verifyToken,
  }) async {
    final callable = _functions.httpsCallable('confirmChangeKey');
    final result = await callable.call({
      'sessionId': sessionId,
      'responses': responses,
      'verifyToken': verifyToken,
      'idempotencyKey': _generateIdempotencyKey(),
    });

    final data = result.data as Map<String, dynamic>;
    return data['ok'] ?? false;
  }

  /// Finalize transfer after successful key change
  Future<void> finalizeTransfer({
    required String sessionId,
    required String newOwnerId,
  }) async {
    final callable = _functions.httpsCallable('finalizeTransfer');
    await callable.call({
      'sessionId': sessionId,
      'newOwnerId': newOwnerId,
    });
  }

  /// Forward a base64-encoded APDU to the card
  /// Returns base64-encoded response
  Future<String> _forwardApdu(String apduBase64) async {
    // Decode APDU from base64
    final apduBytes = base64.decode(apduBase64);
    
    // Send to card via NFC
    final responseHex = await FlutterNfcKit.transceive(
      apduBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
    );

    // Convert hex response to bytes
    final responseBytes = _hexToBytes(responseHex);

    // Encode response as base64
    return base64.encode(responseBytes);
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Generate idempotency key for replay protection
  String _generateIdempotencyKey() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (DateTime.now().microsecondsSinceEpoch % 1000).toString();
  }
}

/// Example usage
class TransferExample {
  final DESFireForwarder _forwarder = DESFireForwarder();

  /// Complete transfer flow
  Future<void> performTransfer({
    required String tokenId,
    required String currentUserId,
    required String newUserId,
  }) async {
    try {
      print('Starting authentication...');
      
      // 1. Begin authentication (polls for NFC)
      final sessionId = await _forwarder.beginAuthentication(
        tokenId: tokenId,
        userId: currentUserId,
      );
      
      print('Authenticated. Session: $sessionId');
      
      // 2. Change key on card
      print('Changing key...');
      final keyChanged = await _forwarder.changeKey(
        sessionId: sessionId,
        targetKey: 'new',
      );
      
      if (!keyChanged) {
        throw Exception('Key change failed');
      }
      
      print('Key changed successfully');
      
      // 3. Finalize transfer in Firestore
      print('Finalizing transfer...');
      await _forwarder.finalizeTransfer(
        sessionId: sessionId,
        newOwnerId: newUserId,
      );
      
      print('Transfer complete!');
    } catch (e) {
      print('Transfer failed: $e');
      rethrow;
    }
  }
} 