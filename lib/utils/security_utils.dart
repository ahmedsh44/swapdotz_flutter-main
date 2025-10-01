// Implementation 4: Error Handling and Security
import 'dart:typed_data';
import '../services/aes_helper.dart';

class DESFireSecurity {
  static const int MAX_AUTH_ATTEMPTS = 3;
  int _authAttempts = 0;

  Future<void> secureTransaction(Function transaction) async {
    try {
      await transaction();
      _authAttempts = 0; // Reset on success
    } catch (e) {
      _authAttempts++;
      if (_authAttempts >= MAX_AUTH_ATTEMPTS) {
        throw Exception('Maximum authentication attempts exceeded');
      }
      rethrow;
    }
  }

  static Uint8List diversifyKey(Uint8List masterKey, Uint8List cardUID) {
    // Key diversification based on card UID
    final diversifier = Uint8List.fromList([
      ...cardUID.sublist(0, 4),
      ...List.filled(12, 0x00)
    ]);
    
    return AESHelper.encryptAES(diversifier, masterKey, 
        Uint8List.fromList(List.filled(16, 0)));
  }
}