/// STRICTLY follows dumb pipe architecture - no crypto logic client-side
import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'secure_logger.dart';

class APDURelayService {
  static final SecureLogger _logger = SecureLogger();
  bool _debugMode = false;

  /// Pure APDU relay - forwards opaque data without interpretation
  Future<APDUResponse> relayAPDU(APDUCommand command) async {
    try {
      _logAPDU('SENDING', command, redactSensitive: !_debugMode);
      
      // Pure pass-through - no crypto, no interpretation
      final response = await FlutterNfcKit.transceive(command.data);
      
      final apduResponse = APDUResponse(
        data: Uint8List.fromList(response),
        sw1: response.length > 1 ? response[response.length - 2] : 0x00,
        sw2: response.length > 0 ? response[response.length - 1] : 0x00,
      );
      
      _logAPDUResponse('RECEIVED', apduResponse, redactSensitive: !_debugMode);
      
      return apduResponse;
    } catch (e) {
      _logger.error('APDU relay failed: $e');
      rethrow;
    }
  }

  /// Relay multiple APDUs in transaction (for atomic operations)
  Future<List<APDUResponse>> relayAPDUChain(List<APDUCommand> commands) async {
    final responses = <APDUResponse>[];
    
    for (final command in commands) {
      final response = await relayAPDU(command);
      responses.add(response);
      
      // Check status word - stop chain on error
      if (!response.isSuccess) {
        _logger.warning('APDU chain interrupted by error: ${response.statusString}');
        break;
      }
    }
    
    return responses;
  }

  void _logAPDU(String direction, APDUCommand command, {bool redactSensitive = true}) {
    if (redactSensitive) {
      _logger.info('$direction APDU: ${command.description} [REDACTED]');
    } else {
      _logger.debug('$direction APDU: ${command.description} '
                   'Data: ${_bytesToHex(command.data)}');
    }
  }

  void _logAPDUResponse(String direction, APDUResponse response, {bool redactSensitive = true}) {
    final statusInfo = 'SW: ${response.statusString}';
    
    if (redactSensitive || response.data.isEmpty) {
      _logger.info('$direction Response: $statusInfo [REDACTED]');
    } else {
      _logger.debug('$direction Response: $statusInfo '
                   'Data: ${_bytesToHex(response.data)}');
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  /// Enable debug mode ONLY for development (removed in production)
  void setDebugMode(bool enabled) {
    _debugMode = enabled;
    _logger.setDebugMode(enabled);
    _logger.warning('DEBUG MODE: ${enabled ? "ENABLED" : "DISABLED"}');
  }
}

/// Opaque APDU command container - server provides full bytes
class APDUCommand {
  final Uint8List data;
  final String description; // For logging only
  
  APDUCommand({required this.data, required this.description});
}

/// APDU response container - raw bytes returned to server
class APDUResponse {
  final Uint8List data;
  final int sw1;
  final int sw2;
  
  APDUResponse({required this.data, required this.sw1, required this.sw2});
  
  int get statusWord => (sw1 << 8) | sw2;
  String get statusString => '${sw1.toRadixString(16)}:${sw2.toRadixString(16)}';
  bool get isSuccess => sw1 == 0x90 && sw2 == 0x00;
  bool get needsMoreData => sw1 == 0x61; // More data available
}