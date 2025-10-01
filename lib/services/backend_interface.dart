/// Handles communication with secure backend server
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/apdu_models.dart'; // Add this import

class BackendInterface {
  final String _backendUrl;
  final String _apiKey;
  
  BackendInterface({required String backendUrl, required String apiKey})
      : _backendUrl = backendUrl,
        _apiKey = apiKey;

  /// Initialize a new session with the backend
  static Future<String> initializeSession(String cardId) async {
    // For now, return a mock session ID
    // In production, this would make an API call to your backend
    return 'session_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Clean up session resources
  static Future<void> cleanupSession(String sessionId) async {
    // Implement session cleanup if needed
    print('Cleaning up session: $sessionId');
  }

  /// Get APDU commands for authentication from backend
  Future<List<APDUCommand>> getAuthenticationAPDUs(String cardId, int keyNumber) async {
    final response = await http.post(
      Uri.parse('$_backendUrl/auth/start'),
      headers: _getHeaders(),
      body: jsonEncode({'cardId': cardId, 'keyNumber': keyNumber}),
    );

    if (response.statusCode != 200) {
      throw Exception('Backend error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return _parseAPDUCommands(data['apduChain']);
  }

  /// Send APDU response to backend for processing
  Future<BackendResponse> sendAPDUResponse(APDUResponse response, String sessionId) async {
    final result = await http.post(
      Uri.parse('$_backendUrl/apdu/process'),
      headers: _getHeaders(),
      body: jsonEncode({
        'sessionId': sessionId,
        'responseData': base64.encode(Uint8List.fromList(response.data)),
        'statusString': response.statusString,
      }),
    );

    return BackendResponse.fromJson(jsonDecode(result.body));
  }

  /// Get next APDU in chain from backend
  Future<APDUCommand> getNextAPDU(String sessionId, APDUResponse lastResponse) async {
    final result = await http.post(
      Uri.parse('$_backendUrl/apdu/next'),
      headers: _getHeaders(),
      body: jsonEncode({
        'sessionId': sessionId,
        'lastResponse': base64.encode(Uint8List.fromList(lastResponse.data)),
        'lastStatus': lastResponse.statusString,
      }),
    );

    final data = jsonDecode(result.body);
    return _parseAPDUCommand(data['nextCommand']);
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
      'X-Client-Type': 'flutter-nfc-relay',
    };
  }

  List<APDUCommand> _parseAPDUCommands(List<dynamic> apduList) {
    return apduList.map((apdu) => APDUCommand(
      instruction: apdu['instruction'] ?? 'UNKNOWN',
      data: Uint8List.fromList(base64.decode(apdu['data'])),
      description: apdu['description'] ?? 'Unknown command',
    )).toList();
  }

  APDUCommand _parseAPDUCommand(Map<String, dynamic> apduData) {
    return APDUCommand(
      instruction: apduData['instruction'] ?? 'UNKNOWN',
      data: Uint8List.fromList(base64.decode(apduData['data'])),
      description: apduData['description'] ?? 'Next command',
    );
  }
}

class BackendResponse {
  final bool success;
  final String? nextAction;
  final List<APDUCommand>? nextCommands;
  final String? sessionId;
  final String? error;

  BackendResponse({
    required this.success,
    this.nextAction,
    this.nextCommands,
    this.sessionId,
    this.error,
  });

  factory BackendResponse.fromJson(Map<String, dynamic> json) {
    return BackendResponse(
      success: json['success'] ?? false,
      nextAction: json['nextAction'],
      nextCommands: json['nextCommands'] != null 
          ? _parseCommands(json['nextCommands'])
          : null,
      sessionId: json['sessionId'],
      error: json['error'],
    );
  }

  static List<APDUCommand> _parseCommands(List<dynamic> commands) {
    return commands.map((cmd) => APDUCommand(
      instruction: cmd['instruction'] ?? 'UNKNOWN',
      data: Uint8List.fromList(base64.decode(cmd['data'])),
      description: cmd['description'] ?? 'Unknown command',
    )).toList();
  }
}