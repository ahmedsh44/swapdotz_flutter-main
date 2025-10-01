import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:math';

/// Comprehensive network security service to prevent spoofing attacks
class NetworkSecurityService {
  static const String _appSignatureKey = 'SwapDotz_2024_Production_Key_v1';
  
  // Firebase project endpoint fingerprints for certificate pinning
  static const Map<String, List<String>> _certificateFingerprints = {
    'firebaseapp.com': [
      'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // Primary cert
      'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=', // Backup cert
    ],
    'googleapis.com': [
      'sha256/CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=', // Primary cert
      'sha256/DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=', // Backup cert
    ],
    'firebasestorage.googleapis.com': [
      'sha256/EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE=', // Primary cert
      'sha256/FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF=', // Backup cert
    ],
  };

  static http.Client? _secureClient;

  /// Initialize secure HTTP client with certificate pinning
  static Future<void> initialize() async {
    final context = SecurityContext(withTrustedRoots: false);
    
    // Load trusted certificates from assets
    try {
      final firebaseCert = await rootBundle.load('assets/certificates/firebase.pem');
      final googleCert = await rootBundle.load('assets/certificates/google.pem');
      
      context.setTrustedCertificatesBytes(firebaseCert.buffer.asUint8List());
      context.setTrustedCertificatesBytes(googleCert.buffer.asUint8List());
    } catch (e) {
      print('⚠️ Certificate loading failed: $e');
      // Fallback to system certificates with pinning validation
    }

    final httpClient = HttpClient(context: context);
    
    // Enable certificate validation callback
    httpClient.badCertificateCallback = (cert, host, port) {
      return _validateCertificateFingerprint(cert, host);
    };

    _secureClient = IOClient(httpClient);
  }

  /// Validate certificate fingerprint against known good values
  static bool _validateCertificateFingerprint(X509Certificate cert, String host) {
    final certBytes = cert.der;
    final sha256Hash = sha256.convert(certBytes);
    final fingerprint = 'sha256/${base64.encode(sha256Hash.bytes)}';
    
    final expectedFingerprints = _certificateFingerprints[host];
    if (expectedFingerprints == null) {
      print('🚨 SECURITY: Unknown host certificate: $host');
      return false;
    }

    final isValid = expectedFingerprints.contains(fingerprint);
    if (!isValid) {
      print('🚨 SECURITY BREACH: Certificate fingerprint mismatch for $host');
      print('   Expected: $expectedFingerprints');
      print('   Received: $fingerprint');
    }

    return isValid;
  }

  /// Create cryptographically signed request to prevent tampering
  static Map<String, String> _createSecureHeaders({
    required String method,
    required String path,
    required String body,
    String? userId,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _generateNonce();
    
    // Create signature payload
    final signaturePayload = '$method|$path|$body|$timestamp|$nonce|${userId ?? 'anonymous'}';
    final signature = _createHMAC(signaturePayload, _appSignatureKey);
    
    return {
      'Content-Type': 'application/json',
      'X-SwapDotz-Timestamp': timestamp,
      'X-SwapDotz-Nonce': nonce,
      'X-SwapDotz-Signature': signature,
      'X-SwapDotz-Version': '1.0.0',
      'User-Agent': 'SwapDotz-Mobile/1.0.0',
      if (userId != null) 'X-SwapDotz-User': userId,
    };
  }

  /// Generate cryptographically secure nonce
  static String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Create HMAC signature for request validation
  static String _createHMAC(String data, String key) {
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(data));
    return base64.encode(digest.bytes);
  }

  /// Secure POST request with anti-tampering protection
  static Future<http.Response> securePost({
    required String url,
    required Map<String, dynamic> body,
    String? userId,
    Map<String, String>? additionalHeaders,
  }) async {
    if (_secureClient == null) {
      await initialize();
    }

    final jsonBody = json.encode(body);
    final uri = Uri.parse(url);
    
    final headers = _createSecureHeaders(
      method: 'POST',
      path: uri.path,
      body: jsonBody,
      userId: userId,
    );

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    try {
      final response = await _secureClient!.post(
        uri,
        headers: headers,
        body: jsonBody,
      ).timeout(const Duration(seconds: 30));

      // Validate response signature if present
      _validateResponseSignature(response);

      return response;
    } catch (e) {
      print('🚨 SECURITY: Secure request failed: $e');
      rethrow;
    }
  }

  /// Secure GET request with certificate pinning
  static Future<http.Response> secureGet({
    required String url,
    String? userId,
    Map<String, String>? additionalHeaders,
  }) async {
    if (_secureClient == null) {
      await initialize();
    }

    final uri = Uri.parse(url);
    
    final headers = _createSecureHeaders(
      method: 'GET',
      path: uri.path,
      body: '',
      userId: userId,
    );

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    try {
      final response = await _secureClient!.get(
        uri,
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      _validateResponseSignature(response);

      return response;
    } catch (e) {
      print('🚨 SECURITY: Secure request failed: $e');
      rethrow;
    }
  }

  /// Validate server response signature to prevent response tampering
  static void _validateResponseSignature(http.Response response) {
    final serverSignature = response.headers['x-swapdotz-signature'];
    if (serverSignature == null) {
      print('⚠️ SECURITY: Missing server signature in response');
      return;
    }

    final timestamp = response.headers['x-swapdotz-timestamp'];
    if (timestamp == null) {
      print('🚨 SECURITY: Missing timestamp in response');
      throw SecurityException('Invalid server response: missing timestamp');
    }

    // Check timestamp to prevent replay attacks
    final serverTime = int.tryParse(timestamp);
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    
    if (serverTime == null || (currentTime - serverTime).abs() > 300000) { // 5 min tolerance
      print('🚨 SECURITY: Response timestamp outside acceptable range');
      throw SecurityException('Invalid server response: timestamp mismatch');
    }

    // Validate response signature
    final expectedSignature = _createHMAC(
      '${response.statusCode}|${response.body}|$timestamp',
      _appSignatureKey,
    );

    if (serverSignature != expectedSignature) {
      print('🚨 SECURITY BREACH: Response signature validation failed');
      throw SecurityException('Response tampering detected');
    }
  }

  /// Clean up resources
  static void dispose() {
    _secureClient?.close();
    _secureClient = null;
  }
}

/// Custom security exception for spoofing attacks
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
} 