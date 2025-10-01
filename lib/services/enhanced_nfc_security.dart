// Add to EnhancedNFCSecurity class
static Future<SecurityValidation> validateAESAuthFlow(NFCTag tag, Uint8List testKey) async {
  try {
    // Send test authentication command
    final testCmd = Uint8List.fromList([0xAA, 0x00]);
    final response = await FlutterNfcKit.transceive(testCmd);
    
    // Analyze response to detect CMAC vs encryption
    final isEncryptedFlow = AESHelper.isEncryptedNonce(response, testKey);
    final isValidLength = response.length == 16;
    
    return SecurityValidation(
      isValid: isEncryptedFlow,
      detectedFlow: isEncryptedFlow ? 'encrypted_nonce' : 'cmac_or_other',
      recommendations: isEncryptedFlow 
          ? [] 
          : ['Card may be using CMAC instead of encrypted nonces'],
      metadata: {
        'response_length': response.length,
        'is_encrypted_pattern': isEncryptedFlow,
        'expected_flow': 'encrypted_nonce'
      }
    );
  } catch (e) {
    return SecurityValidation(
      isValid: false,
      detectedFlow: 'unknown',
      recommendations: ['Unable to determine auth flow: $e'],
      metadata: {'error': e.toString()}
    );
  }
}

// Add this class definition at the bottom of the file
class SecurityValidation {
  final bool isValid;
  final String detectedFlow;
  final List<String> recommendations;
  final Map<String, dynamic> metadata;

  SecurityValidation({
    required this.isValid,
    required this.detectedFlow,
    required this.recommendations,
    required this.metadata,
  });
}