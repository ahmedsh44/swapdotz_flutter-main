import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'backend_interface.dart';
import 'secure_logger.dart';

class NFCService {
  /// Main method for backend-driven NFC operations
  static Future<void> executeSecureOperation({
    required String operationType,
    required Map<String, dynamic> parameters,
    required String iosAlertMessage,
  }) async {
    String? sessionId;
    
    try {
      // 1. Initialize session with backend - FIXED PARAMETERS
      final cardId = parameters['cardId'] ?? 'default_card';
      sessionId = await BackendInterface.initializeSession(cardId);
      
      // Use SecureLogger properly
      print('Session started: $sessionId');

      // 2. Execute the NFC operation
      await _performNFCOperation(
        operationType: operationType,
        parameters: parameters,
        iosAlertMessage: iosAlertMessage,
        sessionId: sessionId!,
      );

      print('Operation completed');
      
    } catch (e) {
      print('Operation failed: $e');
      rethrow;
    } finally {
      // Cleanup
      if (sessionId != null) {
        await BackendInterface.cleanupSession(sessionId);
      }
      await FlutterNfcKit.finish();
    }
  }

  /// ADDED: Method called from main.dart
  static Future<Uint8List> transceiveAPDU(Uint8List apdu) async {
    try {
      final response = await FlutterNfcKit.transceive(apdu);
      return Uint8List.fromList(response);
    } catch (e) {
      print('APDU transceive failed: $e');
      rethrow;
    }
  }

  /// ADDED: Method called from seller_verification_service.dart
  static Future<dynamic> secureNFCOperation(Function operation) async {
    try {
      return await operation();
    } catch (e) {
      print('Secure NFC operation failed: $e');
      rethrow;
    }
  }

  /// ADDED: Internal method to perform NFC operations
  static Future<void> _performNFCOperation({
    required String operationType,
    required Map<String, dynamic> parameters,
    required String iosAlertMessage,
    required String sessionId,
  }) async {
    try {
      // Start NFC session
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: iosAlertMessage,
      );

      // Based on operation type, perform different actions
      switch (operationType) {
        case 'authenticate':
          // Authentication logic would go here
          break;
        case 'read':
          // Read logic would go here
          break;
        case 'write':
          // Write logic would go here
          break;
        case 'changekey':
          // Change key logic would go here
          break;
        default:
          throw Exception('Unknown operation type: $operationType');
      }

      print('NFC operation $operationType completed successfully');
    } catch (e) {
      print('NFC operation failed: $e');
      rethrow;
    }
  }

  /// Quick methods for common operations
  static Future<void> authenticate() async {
    await executeSecureOperation(
      operationType: 'authenticate',
      parameters: {'keyNumber': 0},
      iosAlertMessage: 'Hold card to authenticate',
    );
  }

  static Future<void> readData(int fileNumber, int offset, int length) async {
    await executeSecureOperation(
      operationType: 'read',
      parameters: {'fileNumber': fileNumber, 'offset': offset, 'length': length},
      iosAlertMessage: 'Hold card to read data',
    );
  }

  static Future<void> writeData(int fileNumber, int offset, Uint8List data) async {
    await executeSecureOperation(
      operationType: 'write',
      parameters: {
        'fileNumber': fileNumber,
        'offset': offset,
        'dataLength': data.length,
      },
      iosAlertMessage: 'Hold card to write data',
    );
  }

  static Future<void> changeKey(int keyNumber) async {
    await executeSecureOperation(
      operationType: 'changekey',
      parameters: {'keyNumber': keyNumber},
      iosAlertMessage: 'Hold card to change key',
    );
  }

  /// ADDED: Simple poll method for testing
  static Future<String> pollNFCTag() async {
    try {
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: 'Hold card near device',
      );
      return tag.id;
    } catch (e) {
      print('NFC poll failed: $e');
      rethrow;
    }
  }
}