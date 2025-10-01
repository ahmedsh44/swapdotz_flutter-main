/// Now acts as pure APDU relay - NO CRYPTO LOGIC
import 'apdu_relay_service.dart';
import 'backend_interface.dart';

class DESFireCardManager {
  final APDURelayService _relay = APDURelayService();
  final BackendInterface _backend;
  String? _currentSessionId;

  DESFireCardManager({required BackendInterface backend}) : _backend = backend;

  /// Pure relay authentication - backend handles crypto
  Future<bool> authenticate(int keyNumber, String cardId) async {
    try {
      // 1. Get authentication APDUs from backend
      final authCommands = await _backend.getAuthenticationAPDUs(cardId, keyNumber);
      
      // 2. Relay APDUs to card
      final responses = await _relay.relayAPDUChain(authCommands);
      
      // 3. Send final response to backend for verification
      final lastResponse = responses.last;
      final backendResult = await _backend.sendAPDUResponse(lastResponse, _currentSessionId!);
      
      _currentSessionId = backendResult.sessionId;
      return backendResult.success;
      
    } catch (e) {
      throw Exception('Authentication relay failed: $e');
    }
  }

  /// Read data via APDU relay
  Future<Uint8List> readData(int fileNumber, int offset, int length) async {
    // Backend provides exact APDU sequence
    final readCommands = await _backend.getReadAPDUChain(
      _currentSessionId!, fileNumber, offset, length);
    
    final responses = await _relay.relayAPDUChain(readCommands);
    final lastResponse = responses.last;
    
    if (!lastResponse.isSuccess) {
      throw Exception('Read failed: ${lastResponse.statusString}');
    }
    
    // Backend decrypts and verifies the data
    final backendResult = await _backend.sendAPDUResponse(lastResponse, _currentSessionId!);
    
    if (!backendResult.success) {
      throw Exception('Backend rejected read data: ${backendResult.error}');
    }
    
    return lastResponse.data; // Or let backend return decrypted data
  }

  /// Safe write with backup file (atomic operation)
  Future<void> writeDataSafe(int fileNumber, int backupFile, Uint8List data) async {
    // Backend handles transaction logic and provides APDUs
    final writeCommands = await _backend.getSafeWriteAPDUChain(
      _currentSessionId!, fileNumber, backupFile, data);
    
    final responses = await _relay.relayAPDUChain(writeCommands);
    
    // Verify all operations succeeded
    for (final response in responses) {
      if (!response.isSuccess) {
        throw Exception('Safe write failed: ${response.statusString}');
      }
    }
  }

  /// Rekey operation relayed to backend
  Future<void> rekey(int oldKeyNumber, int newKeyNumber) async {
    final rekeyCommands = await _backend.getRekeyAPDUChain(
      _currentSessionId!, oldKeyNumber, newKeyNumber);
    
    final responses = await _relay.relayAPDUChain(rekeyCommands);
    
    if (!responses.last.isSuccess) {
      throw Exception('Rekey failed: ${responses.last.statusString}');
    }
  }
}