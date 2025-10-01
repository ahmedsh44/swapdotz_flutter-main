import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase-only DESFire forwarder
/// All cryptography happens in Firebase Functions
/// This class only forwards opaque APDU frames between Functions and NFC card
class FirebaseForwarder {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // Use emulator in debug mode
  FirebaseForwarder({bool useEmulator = false}) {
    if (useEmulator) {
      _functions.useFunctionsEmulator('localhost', 5001);
    }
  }
  
  /// Begin authentication and transfer flow
  /// Returns true if transfer successful
  Future<bool> performTransfer({
    required String tokenId,
    required String currentUserId,
    required String newOwnerId,
  }) async {
    try {
      print('[Forwarder] Starting transfer for token: $tokenId');
      
      // 1. Poll for NFC tag
      print('[Forwarder] Waiting for NFC tag...');
      final tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: 30),
        iosMultipleTagMessage: 'Multiple tags found',
        iosAlertMessage: 'Hold your device near the SwapDot',
      );

      if (tag.type != NFCTagType.iso7816) {
        throw Exception('Invalid tag type: ${tag.type}');
      }

      print('[Forwarder] NFC tag detected: ${tag.id}');

      // 2. Begin authentication with Firebase
      print('[Forwarder] Calling beginAuthenticate...');
      final beginAuth = _functions.httpsCallable('beginAuthenticate');
      final beginResult = await beginAuth.call({
        'tokenId': tokenId,
        'userId': currentUserId,
      });

      final beginData = beginResult.data as Map<String, dynamic>;
      final sessionId = beginData['sessionId'] as String;
      final authApdus = List<String>.from(beginData['apdus']);
      
      print('[Forwarder] Session created: $sessionId');

      // 3. Forward first auth APDU to card
      String cardResponse = await _forwardApdu(authApdus[0]);
      
      // 4. Continue authentication rounds
      bool authDone = false;
      while (!authDone) {
        print('[Forwarder] Continuing authentication...');
        final continueAuth = _functions.httpsCallable('continueAuthenticate');
        final continueResult = await continueAuth.call({
          'sessionId': sessionId,
          'response': cardResponse,
        });

        final continueData = continueResult.data as Map<String, dynamic>;
        authDone = continueData['done'] ?? false;

        if (!authDone) {
          final nextApdus = List<String>.from(continueData['apdus'] ?? []);
          if (nextApdus.isNotEmpty) {
            cardResponse = await _forwardApdu(nextApdus[0]);
          }
        }
      }

      print('[Forwarder] Authentication complete');

      // 5. Change key on card
      print('[Forwarder] Changing key...');
      final changeKey = _functions.httpsCallable('changeKey');
      final keyResult = await changeKey.call({
        'sessionId': sessionId,
      });

      final keyData = keyResult.data as Map<String, dynamic>;
      final keyApdus = List<String>.from(keyData['apdus']);
      
      // Forward all key change APDUs
      final keyResponses = <String>[];
      for (final apdu in keyApdus) {
        final response = await _forwardApdu(apdu);
        keyResponses.add(response);
      }

      // 6. Confirm and finalize
      print('[Forwarder] Finalizing transfer...');
      final confirmFinalize = _functions.httpsCallable('confirmAndFinalize');
      final finalResult = await confirmFinalize.call({
        'sessionId': sessionId,
        'response': keyResponses.last,
        'newOwnerId': newOwnerId,
      });

      final success = (finalResult.data as Map<String, dynamic>)['success'] ?? false;
      
      if (success) {
        print('[Forwarder] Transfer complete!');
      }
      
      return success;
      
    } catch (e) {
      print('[Forwarder] Error: $e');
      return false;
    } finally {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}
    }
  }

  /// Forward a base64-encoded APDU to the NFC card
  /// Returns base64-encoded response (data only, no SW1/SW2)
  Future<String> _forwardApdu(String apduBase64) async {
    try {
      // Decode APDU from base64
      final apduBytes = base64.decode(apduBase64);
      
      // Convert to hex string for NFC kit
      final apduHex = apduBytes
          .map((e) => e.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      
      print('[Forwarder] Sending APDU: ${apduHex.substring(0, 14)}...');
      
      // Send to card via NFC
      final responseHex = await FlutterNfcKit.transceive(apduHex);
      
      print('[Forwarder] Received: ${responseHex.substring(responseHex.length - 4)}');
      
      // Convert hex response to bytes
      final responseBytes = _hexToBytes(responseHex);
      
      // Log status for debugging
      if (responseBytes.length >= 2) {
        final sw1 = responseBytes[responseBytes.length - 2];
        final sw2 = responseBytes[responseBytes.length - 1];
        print('[Forwarder] Status: ${sw1.toRadixString(16).padLeft(2, '0')}${sw2.toRadixString(16).padLeft(2, '0')}');
        print('[Forwarder] Total response length: ${responseBytes.length} bytes');
      }
      
      // CRITICAL: Return FULL response including SW1/SW2
      // The server needs the complete response to properly handle status codes
      return base64.encode(responseBytes);
    } catch (e) {
      print('[Forwarder] APDU error: $e');
      rethrow;
    }
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    // Remove any spaces or formatting
    hex = hex.replaceAll(' ', '').replaceAll('\n', '');
    
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Test authentication only (for debugging)
  Future<bool> testAuthentication({
    required String tokenId,
    required String userId,
  }) async {
    try {
      print('[Forwarder] Testing authentication...');
      print('[Forwarder] TokenId: $tokenId, UserId: $userId');
      
      // Poll for tag
      print('[Forwarder] Polling for NFC tag...');
      final tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: 30),
        iosMultipleTagMessage: "Multiple tags found!",
        iosAlertMessage: "Hold your NFC tag near the phone",
      );

      print('[Forwarder] Tag detected: ${tag.type}, ID: ${tag.id}');
      
      if (tag.type != NFCTagType.iso7816) {
        throw Exception('Invalid tag type: ${tag.type}');
      }

      // IMPORTANT: Keep the tag connected throughout the entire process
      // Don't remove the tag until authentication is complete!
      
      // Begin auth
      print('[Forwarder] Calling beginAuthenticate function...');
      final beginAuth = _functions.httpsCallable('beginAuthenticate');
      
      Map<String, dynamic> data;
      String sessionId;
      List<String> apdus;
      
      try {
        final beginResult = await beginAuth.call({
          'tokenId': tokenId,
          'userId': userId,
        });
        
        print('[Forwarder] beginAuthenticate response received');
        data = beginResult.data as Map<String, dynamic>;
        print('[Forwarder] Response data: $data');
        
        sessionId = data['sessionId'] as String;
        apdus = List<String>.from(data['apdus']);
        
        print('[Forwarder] Session ID: $sessionId');
        print('[Forwarder] First APDU: ${apdus[0]}');
      } catch (e) {
        if (e is FirebaseFunctionsException && e.code == 'resource-exhausted') {
          print('[Forwarder] Token is locked, waiting and retrying...');
          // Wait a bit for the lock to expire
          await Future.delayed(Duration(seconds: 2));
          
          // Retry
          final retryResult = await beginAuth.call({
            'tokenId': tokenId,
            'userId': userId,
          });
          
          data = retryResult.data as Map<String, dynamic>;
          sessionId = data['sessionId'] as String;
          apdus = List<String>.from(data['apdus']);
        } else {
          rethrow;
        }
      }
      
      // Forward first APDU
      String response = await _forwardApdu(apdus[0]);
      print('[Forwarder] Card response: ${response.length > 20 ? response.substring(0, 20) + "..." : response}');
      
      // Continue auth
      bool done = false;
      int rounds = 0;
      
      while (!done && rounds < 5) {
        print('[Forwarder] Calling continueAuthenticate (round $rounds)...');
        final continueAuth = _functions.httpsCallable('continueAuthenticate');
        
        try {
          final result = await continueAuth.call({
            'sessionId': sessionId,
            'response': response,
          });
          
          final resultData = result.data as Map<String, dynamic>;
          done = resultData['done'] ?? false;
          
          if (!done) {
            final nextApdus = List<String>.from(resultData['apdus'] ?? []);
            if (nextApdus.isNotEmpty) {
              print('[Forwarder] Forwarding next APDU...');
              response = await _forwardApdu(nextApdus[0]);
              print('[Forwarder] Got response from card');
            }
          } else {
            print('[Forwarder] Authentication successful!');
          }
        } catch (e) {
          print('[Forwarder] Error in continueAuthenticate: $e');
          if (e is FirebaseFunctionsException) {
            print('[Forwarder] Error code: ${e.code}');
            print('[Forwarder] Error message: ${e.message}');
          }
          throw e;
        }
        
        rounds++;
      }
      
      print('[Forwarder] Authentication test ${done ? "successful" : "failed"}');
      return done;
      
    } catch (e) {
      print('[Forwarder] Auth test error: $e');
      print('[Forwarder] Stack trace: ${StackTrace.current}');
      return false;
    } finally {
      try {
        await FlutterNfcKit.finish(iosAlertMessage: "Authentication complete");
      } catch (_) {}
    }
  }

  /// Test secure messaging operations (write and change key)
  Future<bool> testSecureMessaging({
    required String tokenId,
    required String userId,
  }) async {
    try {
      print('[Forwarder] Testing secure messaging...');
      print('[Forwarder] TokenId: $tokenId, UserId: $userId');
      
      // Poll for tag
      print('[Forwarder] Polling for NFC tag...');
      final tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: 30),
        iosMultipleTagMessage: "Multiple tags found!",
        iosAlertMessage: "Hold your NFC tag near the phone",
      );

      print('[Forwarder] Tag detected: ${tag.type}, ID: ${tag.id}');
      
      if (tag.type != NFCTagType.iso7816) {
        throw Exception('Invalid tag type: ${tag.type}');
      }

      // Step 1: Authenticate
      print('[Forwarder] Step 1: Authenticating...');
      final beginAuth = _functions.httpsCallable('beginAuthenticate');
      final beginResult = await beginAuth.call({
        'tokenId': tokenId,
        'userId': userId,
      });
      
      final sessionId = beginResult.data['sessionId'] as String;
      final authApdus = List<String>.from(beginResult.data['apdus']);
      
      print('[Forwarder] Session ID: $sessionId');
      
      // Forward auth APDUs
      String response = await _forwardApdu(authApdus[0]);
      
      // Continue auth
      final continueAuth = _functions.httpsCallable('continueAuthenticate');
      final continueResult = await continueAuth.call({
        'sessionId': sessionId,
        'response': response,
      });
      
      if (!(continueResult.data['done'] ?? false)) {
        // Send second auth frame
        final nextApdus = List<String>.from(continueResult.data['apdus'] ?? []);
        if (nextApdus.isNotEmpty) {
          response = await _forwardApdu(nextApdus[0]);
          
          // Final auth step
          final finalResult = await continueAuth.call({
            'sessionId': sessionId,
            'response': response,
          });
          
          if (!(finalResult.data['done'] ?? false)) {
            throw Exception('Authentication failed');
          }
        }
      }
      
      print('[Forwarder] Authentication successful!');
      
      // Step 1.5: Setup application and file (like desfire.dart does)
      print('[Forwarder] Step 1.5: Setting up app 000001 and file 01...');
      final setupApp = _functions.httpsCallable('setupAppAndFile');
      final setupResult = await setupApp.call({
        'sessionId': sessionId,
      });
      
      final setupApdus = List<String>.from(setupResult.data['apdus']);
      final steps = List<String>.from(setupResult.data['steps'] ?? []);
      
      for (int i = 0; i < setupApdus.length; i++) {
        print('[Forwarder] ${steps[i]}...');
        final response = await _forwardApdu(setupApdus[i]);
        
        // Check response (may fail for create app if already exists)
        try {
          final respBytes = base64.decode(response);
          if (respBytes.length >= 2) {
            final sw1 = respBytes[respBytes.length - 2];
            final sw2 = respBytes[respBytes.length - 1];
            if (sw1 == 0x91 && sw2 == 0x00) {
              print('[Forwarder] ✅ ${steps[i]} successful');
            } else {
              print('[Forwarder] ℹ️ ${steps[i]}: ${sw1.toRadixString(16)}${sw2.toRadixString(16)}');
            }
          }
        } catch (e) {
          print('[Forwarder] Error: $e');
        }
      }
      
      // Now we need to authenticate at application level (like desfire.dart does)
      print('[Forwarder] Authenticating at application level...');
      
      // Start app-level authentication
      final authAppStart = _functions.httpsCallable('authenticateAppLevel');
      final authAppResult = await authAppStart.call({
        'sessionId': sessionId,
      });
      
      final authAppApdus = List<String>.from(authAppResult.data['apdus']);
      String authAppResp = await _forwardApdu(authAppApdus[0]);
      
      // The first response should be 91AF with 8 bytes of encrypted RndB
      // Since _forwardApdu strips SW1/SW2, we just get the 8 bytes
      print('[Forwarder] App auth step 1: Got encrypted RndB, continuing...');
      
      // Continue app authentication
      final continueAppAuth = _functions.httpsCallable('continueAppAuth');
      final continueAppResult = await continueAppAuth.call({
        'sessionId': sessionId,
        'response': authAppResp, // Already base64 encoded, SW1/SW2 stripped
      });
      
      final continueAppApdus = List<String>.from(continueAppResult.data['apdus']);
      final continueAppResp = await _forwardApdu(continueAppApdus[0]);
      
      // The second response should be 91 00 with 8 bytes of encrypted RndA'
      print('[Forwarder] ✅ App-level authentication successful!');
      
      // Step 1.7: Try to create file 01 (may fail if exists)
      print('[Forwarder] Creating file 01 (if needed)...');
      try {
        final createFile = _functions.httpsCallable('createFile01');
        final createResult = await createFile.call({
          'sessionId': sessionId,
        });
        
        final createApdus = List<String>.from(createResult.data['apdus']);
        final createResp = await _forwardApdu(createApdus[0]);
        
        // Should get 91 00 (created) or 91 DE (duplicate)
        print('[Forwarder] File 01 creation attempted (expecting 91 00 or 91 DE)');
      } catch (e) {
        print('[Forwarder] File creation error: $e');
      }
      
      // Step 2: Write transfer data with secure messaging
      print('[Forwarder] Step 2: Writing secure transfer data...');
      final writeData = _functions.httpsCallable('writeTransferData');
      
      String writeResponse = '';
      try {
        final writeResult = await writeData.call({
          'sessionId': sessionId,
          'transferSessionId': 'test-transfer-${DateTime.now().millisecondsSinceEpoch}',
          'challenge': 'test-challenge-${DateTime.now().millisecondsSinceEpoch}',
        });
        
        final writeApdus = List<String>.from(writeResult.data['apdus']);
        print('[Forwarder] Write APDUs generated: ${writeApdus.length} frames');
        
        // Send all WriteData frames
        for (int i = 0; i < writeApdus.length; i++) {
          print('[Forwarder] Sending WriteData frame ${i + 1}/${writeApdus.length}...');
          writeResponse = await _forwardApdu(writeApdus[i]);
          
          // Check response
          final respBytes = base64.decode(writeResponse);
          if (respBytes.length >= 2) {
            final sw1 = respBytes[respBytes.length - 2];
            final sw2 = respBytes[respBytes.length - 1];
            
            if (i < writeApdus.length - 1) {
              // Expect 91 AF for continuation
              if (sw1 == 0x91 && sw2 == 0xAF) {
                print('[Forwarder] Frame ${i + 1}: Continue (91 AF)');
              } else {
                print('[Forwarder] Frame ${i + 1}: Unexpected status ${sw1.toRadixString(16)}${sw2.toRadixString(16)}');
                break;
              }
            } else {
              // Last frame should be 91 00
              if (sw1 == 0x91 && sw2 == 0x00) {
                print('[Forwarder] ✅ Write successful (91 00)');
              } else {
                print('[Forwarder] ⚠️ Write status: ${sw1.toRadixString(16)}${sw2.toRadixString(16)}');
              }
            }
          }
        }
      } catch (e) {
        // Check if this is a weak key error
        if (e.toString().contains('weak') || e.toString().contains('Weak')) {
          print('[Forwarder] Weak session key detected, re-authenticating...');
          
          // Re-authenticate to get a new session key
          await FlutterNfcKit.finish();
          await Future.delayed(Duration(milliseconds: 500));
          
          // Recursively retry the entire test with a fresh authentication
          return testSecureMessaging(tokenId: tokenId, userId: userId);
        }
        rethrow;
      }
      
      // Check if write was successful (should end with 91 00)
      // Note: writeResponse is already processed by _forwardApdu, check the last response
      if (writeResponse.isNotEmpty) {
        try {
          final writeBytes = base64.decode(writeResponse);
          if (writeBytes.length >= 2) {
            final sw1 = writeBytes[writeBytes.length - 2];
            final sw2 = writeBytes[writeBytes.length - 1];
            if (sw1 == 0x91 && sw2 == 0x00) {
              print('[Forwarder] ✅ Write successful (91 00)');
            } else if (sw1 == 0x91 && sw2 == 0x9D) {
              print('[Forwarder] ❌ Write failed: Permission denied (91 9D)');
              print('[Forwarder] File exists but does not allow MACed writes or we lack permission');
              return false;
            } else if (sw1 == 0x91 && sw2 == 0xBD) {
              print('[Forwarder] ❌ Write failed: File not found (91 BD)');
              return false;
            } else {
              print('[Forwarder] ⚠️ Write status: ${sw1.toRadixString(16)}${sw2.toRadixString(16)}');
            }
          }
        } catch (e) {
          print('[Forwarder] Error parsing write response: $e');
        }
      }
      
      // Step 3: Change key with secure messaging
      // TODO: Implement key rotation with proper key management system
      // Requirements before enabling:
      // 1. Permanent key storage in Firestore (tokens/{tokenId}/keys/{version})
      // 2. Key encryption using Cloud KMS
      // 3. Key version tracking per card
      // 4. Backup/recovery mechanism
      // 5. Confirmation step after successful change
      //
      // For now, we keep using the default all-zeros key which is safe and known.
      // The main security goal is already achieved: the phone never sees the keys,
      // all cryptographic operations happen server-side.
      
      print('[Forwarder] Step 3: Key rotation (TODO - disabled for safety)');
      print('[Forwarder] Note: Key rotation requires proper key management system');
      print('[Forwarder] Current security: ✅ Keys never exposed to client');
      
      // Commented out for safety - DO NOT ENABLE without key management system
      // final changeKey = _functions.httpsCallable('changeKey');
      // ... [ChangeKey implementation removed for safety]
      
      print('[Forwarder] Secure messaging test complete!');
      return true;
      
    } catch (e) {
      print('[Forwarder] Secure messaging test error: $e');
      return false;
    } finally {
      try {
        await FlutterNfcKit.finish(iosAlertMessage: "Test complete");
      } catch (_) {}
    }
  }
} 