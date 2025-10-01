import 'dart:typed_data';

class SecureLogger {
  static bool _debugMode = false;
  static final Set<String> _sensitiveOperations = {
    'authenticate', 'changekey', 'write'
  };

  static void enableDebugMode(bool enable) {
    _debugMode = enable;
    print('Debug mode: ${enable ? "ENABLED" : "DISABLED"}');
  }

  static void logAPDU(String direction, Uint8List apdu, {String? operationId}) {
    final operationType = operationId?.split('-').first ?? 'unknown';
    final isSensitive = _sensitiveOperations.contains(operationType);
    
    if (_debugMode && !isSensitive) {
      // Full logging in debug mode for non-sensitive operations
      print('$direction ${_formatAPDU(apdu)} [${operationId ?? 'N/A'}]');
    } else if (_debugMode && isSensitive) {
      // Redacted logging for sensitive operations even in debug mode
      print('$direction ${_redactSensitiveAPDU(apdu)} [${operationId ?? 'N/A'}] - REDACTED');
    } else {
      // Production: minimal logging
      print('$direction ${apdu.length} bytes [${operationId ?? 'N/A'}]');
    }
  }

  static void logInfo(String message, {String? operationId}) {
    print('ℹ️ INFO: $message [${operationId ?? 'N/A'}]');
  }

  static void logError(String error, {String? operationId}) {
    print('❌ ERROR: $error [${operationId ?? 'N/A'}]');
  }

  static void logSuccess(String message, {String? operationId}) {
    print('✅ SUCCESS: $message [${operationId ?? 'N/A'}]');
  }

  // Private helpers
  static String _formatAPDU(Uint8List apdu) {
    return apdu.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
  }

  static String _redactSensitiveAPDU(Uint8List apdu) {
    if (apdu.length <= 5) return _formatAPDU(apdu);
    
    // Keep header (first 5 bytes) and redact data
    final header = apdu.sublist(0, 5);
    final redactedData = List.filled(apdu.length - 5, 0x00);
    
    return _formatAPDU(Uint8List.fromList([...header, ...redactedData]));
  }
}