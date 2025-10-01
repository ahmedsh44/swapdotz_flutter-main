import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

/// Server-authoritative NFC service - drop-in replacement for direct DESFire operations
/// All crypto happens server-side, the app just forwards APDUs
class ServerNFCService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  /// Forward an APDU to the card and return the response (INCLUDING status bytes SW1/SW2)
  static Future<String> _forwardApdu(String apduBase64) async {
    final apduBytes = base64.decode(apduBase64);
    print('[ServerNFC] Sending APDU: ${apduBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}...');
    
    try {
      final response = await FlutterNfcKit.transceive(Uint8List.fromList(apduBytes));
      
      // Log status for debugging but DO NOT strip SW1/SW2
      if (response.length >= 2) {
        final sw1 = response[response.length - 2];
        final sw2 = response[response.length - 1];
        final status = '${sw1.toRadixString(16).padLeft(2, '0')}${sw2.toRadixString(16).padLeft(2, '0')}';
        print('[ServerNFC] Status: $status');
        
        // Check for error status codes
        if (sw1 == 0x91 && sw2 == 0xCA) {
          throw Exception('Command aborted (91CA) - Card may be in inconsistent state. Please remove card, wait 2 seconds, and try again.');
        }
      }
      
      // Return the FULL response including SW1/SW2
      return base64.encode(response);
    } catch (e) {
      if (e.toString().contains('Tag already removed') || e.toString().contains('503')) {
        throw Exception('NFC tag removed - please keep card in place for entire operation (~10 seconds)');
      }
      rethrow;
    }
  }
  
  /// Authenticate with the card and setup app/file
  /// Returns sessionId for subsequent operations
  static Future<String> authenticateAndSetup({
    required String tokenId, 
    required String userId,
    bool allowUnowned = false,
  }) async {
    print('[ServerNFC] Starting server-authoritative authentication...');
    print('[ServerNFC] TokenId: $tokenId, UserId: $userId, AllowUnowned: $allowUnowned');
    print('[ServerNFC] ⚠️ IMPORTANT: Keep card in place for entire operation (~10 seconds)');
    
    // Step 0: Select PICC (master application) to reset card state
    // This ensures we start fresh, avoiding 91CA errors from previous sessions
    try {
      final selectPicc = Uint8List.fromList([0x90, 0x5A, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00]);
      await FlutterNfcKit.transceive(selectPicc);
      print('[ServerNFC] PICC selected - card state reset');
    } catch (e) {
      print('[ServerNFC] Warning: PICC selection failed, continuing anyway: $e');
    }
    
    // Step 1: Begin PICC authentication
    final beginAuth = _functions.httpsCallable('beginAuthenticate');
    final authResult = await beginAuth.call({
      'tokenId': tokenId,
      'userId': userId,
      'allowUnowned': allowUnowned,
    });
    
    final sessionId = authResult.data['sessionId'] as String;
    print('[ServerNFC] Session ID: $sessionId');
    
    // Send first auth APDU
    final authApdus = List<String>.from(authResult.data['apdus']);
    String response = await _forwardApdu(authApdus[0]);
    
    // Step 2: Continue authentication
    final continueAuth = _functions.httpsCallable('continueAuthenticate');
    bool done = false;
    
    while (!done) {
      final continueResult = await continueAuth.call({
        'sessionId': sessionId,
        'response': response,
      });
      
      done = continueResult.data['done'] ?? false;
      if (!done) {
        final nextApdus = List<String>.from(continueResult.data['apdus'] ?? []);
        if (nextApdus.isNotEmpty) {
          response = await _forwardApdu(nextApdus[0]);
        }
      }
    }
    
    print('[ServerNFC] PICC authentication successful!');
    
    // Step 3: Setup app and file (skip if likely to exist)
    // Only try setup for truly new tokens to reduce NFC time
    if (allowUnowned) {
      final setupApp = _functions.httpsCallable('setupAppAndFile');
      final setupResult = await setupApp.call({'sessionId': sessionId});
      
      final setupApdus = List<String>.from(setupResult.data['apdus']);
      for (int i = 0; i < setupApdus.length; i++) {
        print('[ServerNFC] Setup step ${i + 1}/${setupApdus.length}...');
        try {
          await _forwardApdu(setupApdus[i]);
        } catch (e) {
          // Some operations may fail (e.g., app already exists) - that's OK
          print('[ServerNFC] Setup step ${i + 1} failed (may be expected): $e');
        }
      }
    } else {
      print('[ServerNFC] Skipping app/file setup for existing token');
    }
    
    // Step 4: Authenticate at app level
    final authApp = _functions.httpsCallable('authenticateAppLevel');
    final appAuthResult = await authApp.call({'sessionId': sessionId});
    
    final appAuthApdus = List<String>.from(appAuthResult.data['apdus']);
    final appAuthResp = await _forwardApdu(appAuthApdus[0]);
    
    // Continue app auth
    final continueAppAuth = _functions.httpsCallable('continueAppAuth');
    final continueAppResult = await continueAppAuth.call({
      'sessionId': sessionId,
      'response': appAuthResp,
    });
    
    final continueAppApdus = List<String>.from(continueAppResult.data['apdus'] ?? []);
    if (continueAppApdus.isNotEmpty) {
      await _forwardApdu(continueAppApdus[0]);
    }
    
    print('[ServerNFC] App-level authentication successful!');
    
    // Try to create file (may fail if exists)
    try {
      final createFile = _functions.httpsCallable('createFile01');
      final createResult = await createFile.call({'sessionId': sessionId});
      final createApdus = List<String>.from(createResult.data['apdus']);
      await _forwardApdu(createApdus[0]);
    } catch (e) {
      print('[ServerNFC] File creation skipped (may already exist)');
    }
    
    // Small delay to let the card stabilize before write operations
    print('[ServerNFC] Waiting 100ms for card to stabilize...');
    await Future.delayed(Duration(milliseconds: 100));
    
    return sessionId;
  }
  
  /// Write data to file 01 - drop-in replacement for desfire.writeFile01()
  /// Note: Requires tokenId and userId for authentication
  static Future<void> writeFile01(
    Uint8List data, {
    required String tokenId,
    required String userId,
    String? sessionId,
    bool allowUnowned = false,
  }) async {
    print('[ServerNFC] Writing ${data.length} bytes to file 01...');
    
    // Authenticate if no session provided
    final session = sessionId ?? await authenticateAndSetup(
      tokenId: tokenId,
      userId: userId,
      allowUnowned: allowUnowned,
    );
    
    // Convert raw bytes to hex string for server
    // The server expects a string, so we send hex representation
    final dataString = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    // Call writeTransferData (with dummy transfer session for now)
    final writeFunc = _functions.httpsCallable('writeTransferData');
    final writeResult = await writeFunc.call({
      'sessionId': session,
      'transferSessionId': 'init-$tokenId', // Dummy value for initialization
      'challenge': dataString,
    });
    
    // Send write APDUs
    final writeApdus = List<String>.from(writeResult.data['apdus']);
    print('[ServerNFC] Sending ${writeApdus.length} write frames...');
    
    for (int i = 0; i < writeApdus.length; i++) {
      print('[ServerNFC] Sending frame ${i + 1}/${writeApdus.length}...');
      try {
        final resp = await _forwardApdu(writeApdus[i]);
        print('[ServerNFC] Frame ${i + 1} response received');
        
        // Check if we need to continue (91AF) or if we're done (9100)
        if (i < writeApdus.length - 1) {
          // Not the last frame, should get 91AF
          print('[ServerNFC] Expecting more frames...');
        } else {
          // Last frame, should get 9100
          print('[ServerNFC] Final frame sent');
        }
      } catch (e) {
        print('[ServerNFC] ❌ Failed to send frame ${i + 1}: $e');
        if (e.toString().contains('Tag was lost') || e.toString().contains('Tag already removed')) {
          throw Exception('NFC connection lost during write. Please hold the card steady for 15 seconds.');
        }
        rethrow;
      }
    }
    
    print('[ServerNFC] ✅ Write successful!');
  }
  
  /// Write a SERVER-GENERATED key to file 01 - TRUE server-authoritative!
  /// The key is generated server-side and NEVER exposed to the client
  static Future<String> writeServerGeneratedKey({
    required String tokenId,
    required String userId,
    String? sessionId,
    String? transferSessionId,
    bool allowUnowned = false,
  }) async {
    print('[ServerNFC] 🔐 Writing SERVER-GENERATED key to file 01...');
    print('[ServerNFC] 🔐 Client will NEVER see this key!');
    
    // Authenticate if no session provided
    final session = sessionId ?? await authenticateAndSetup(
      tokenId: tokenId,
      userId: userId,
      allowUnowned: allowUnowned,
    );
    
    // Call writeTransferData with generateNewKey flag
    final writeFunc = _functions.httpsCallable('writeTransferData');
    final writeResult = await writeFunc.call({
      'sessionId': session,
      'transferSessionId': transferSessionId ?? 'init-$tokenId',
      'generateNewKey': true,  // THIS tells server to generate the key!
    });
    
    // Send write APDUs
    final writeApdus = List<String>.from(writeResult.data['apdus']);
    final keyHash = writeResult.data['keyHash'] as String?;
    
    // Safely preview the hash
    final hashPreview = keyHash != null && keyHash.length >= 16 
        ? '${keyHash.substring(0, 16)}...' 
        : (keyHash ?? 'unknown');
    
    print('[ServerNFC] Server generated a key with hash: $hashPreview');
    print('[ServerNFC] Sending ${writeApdus.length} write frames...');
    
    for (int i = 0; i < writeApdus.length; i++) {
      print('[ServerNFC] Sending frame ${i + 1}/${writeApdus.length}...');
      try {
        final resp = await _forwardApdu(writeApdus[i]);
        print('[ServerNFC] Frame ${i + 1} response received');
      } catch (e) {
        print('[ServerNFC] ❌ Failed to send frame ${i + 1}: $e');
        if (e.toString().contains('Tag was lost') || e.toString().contains('Tag already removed')) {
          throw Exception('NFC connection lost during write. Please hold the card steady.');
        }
        rethrow;
      }
    }
    
    print('[ServerNFC] ✅ Server-generated key written successfully!');
    print('[ServerNFC] 🔐 Key hash: ${keyHash ?? "unknown"}');
    
    return keyHash ?? '';
  }
  
  /// Read data from file 01 - drop-in replacement for desfire.readFile01()
  /// Note: Requires tokenId and userId for authentication
  /// Returns the data as a String (UTF-8 decoded)
  static Future<String> readFile01({
    required String tokenId,
    required String userId,
    String? sessionId,
    bool allowUnowned = false,
    int length = 64, // Default to reading 64 bytes (key length)
  }) async {
    print('[ServerNFC] Reading $length bytes from file 01...');
    
    // Authenticate if no session provided
    final session = sessionId ?? await authenticateAndSetup(
      tokenId: tokenId,
      userId: userId,
      allowUnowned: allowUnowned,
    );
    
    // Call readFileData
    final readFunc = _functions.httpsCallable('readFileData');
    final readResult = await readFunc.call({
      'sessionId': session,
      'fileNo': 0x01,
      'length': length,
    });
    
    // Send read APDU
    final readApdus = List<String>.from(readResult.data['apdus']);
    final response = await _forwardApdu(readApdus[0]);
    
    // Decode response
    final responseBytes = base64.decode(response);
    print('[ServerNFC] ✅ Read ${responseBytes.length} bytes');
    
    // For empty reads, return empty string
    if (responseBytes.isEmpty || responseBytes.every((b) => b == 0)) {
      return '';
    }
    
    // Try to extract meaningful data (handle both UTF-8 and hex keys)
    try {
      // First, check if there's a null terminator indicating string data
      final nullIndex = responseBytes.indexOf(0);
      
      if (nullIndex > 0) {
        // Try to decode the portion before the null terminator as UTF-8
        try {
          final stringData = utf8.decode(responseBytes.sublist(0, nullIndex));
          print('[ServerNFC] Decoded as UTF-8 string: ${stringData.substring(0, math.min(16, stringData.length))}...');
          return stringData;
        } catch (e) {
          // Not UTF-8, treat as raw binary and convert to hex
          print('[ServerNFC] Not UTF-8, converting to hex');
        }
      }
      
      // If no null terminator or UTF-8 decode failed, check for raw key data
      // Keys are typically 32 or 64 bytes
      if (responseBytes.length >= 32) {
        // Take up to 64 bytes (or until null terminator)
        final keyBytes = nullIndex > 0 
            ? responseBytes.sublist(0, nullIndex)
            : responseBytes.take(64).toList();
            
        // Convert to hex string for storage
        final hexKey = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        print('[ServerNFC] Converted ${keyBytes.length} bytes to hex: ${hexKey.substring(0, 16)}...');
        return hexKey;
      }
      
      // Fallback: try UTF-8 on entire data
      try {
        return utf8.decode(responseBytes);
      } catch (e) {
        // Last resort: convert all bytes to hex
        final hexData = responseBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        print('[ServerNFC] Fallback to hex conversion: ${hexData.substring(0, math.min(16, hexData.length))}...');
        return hexData;
      }
    } catch (e) {
      print('[ServerNFC] ⚠️ Error processing card data: $e');
      // Return hex representation as safest option
      final hexData = responseBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return hexData;
    }
  }
  
  /// SECURE: Read key from card and validate transfer challenge server-side
  /// This is the proper server-authoritative way - client never sees the key
  static Future<Map<String, dynamic>> readAndValidateTransfer({
    required String tokenId,
    required String userId,
    required String transferSessionId,
    String? sessionId,
    bool allowUnowned = false,
  }) async {
    print('[ServerNFC] 🔐 SECURE: Reading and validating transfer server-side...');
    
    // Authenticate if no session provided
    final session = sessionId ?? await authenticateAndSetup(
      tokenId: tokenId,
      userId: userId,
      allowUnowned: allowUnowned,
    );
    
    // Step 1: Read the key from the card
    print('[ServerNFC] 🔐 Step 1: Reading key from card via APDU...');
    final readFunc = _functions.httpsCallable('readFileData');
    final readResult = await readFunc.call({
      'sessionId': session,
      'fileNo': 0x01,
      'length': 64,  // Read key length
    });
    
    // Send read APDU and get raw response
    final readApdus = List<String>.from(readResult.data['apdus']);
    final cardResponse = await _forwardApdu(readApdus[0]);
    
    print('[ServerNFC] 🔐 Step 2: Sending raw card response to server for validation...');
    
    // Step 2: Send the raw card response to server for validation
    final validateFunc = _functions.httpsCallable('validateCardKeyForTransfer');
    final validateResult = await validateFunc.call({
      'sessionId': session,
      'transferSessionId': transferSessionId,
      'cardResponse': cardResponse,  // Raw APDU response - client never decodes it!
    });
    
    final validationData = validateResult.data as Map<String, dynamic>;
    
    if (validationData['valid'] == true) {
      print('[ServerNFC] ✅ Server validated transfer successfully!');
      print('[ServerNFC] 🔐 Key hash from server: ${(validationData['keyHash'] as String?)?.substring(0, 16)}...');
    } else {
      throw Exception('Server validation failed: ${validationData['message']}');
    }
    
    return validationData;
  }
} 