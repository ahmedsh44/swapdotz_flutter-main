class APDUCommand {
  final String instruction;
  final List<int> data;
  final String description;
  
  APDUCommand({
    required this.instruction,
    required this.data,
    required this.description,
  });
}

class APDUResponse {
  final List<int> data;
  final String statusString;
  
  APDUResponse({
    required this.data,
    required this.statusString,
  });
}

class BackendResponse {
  final bool success;
  final String? error;
  final List<APDUCommand>? nextCommands;
  final String? sessionId;
  
  BackendResponse({
    required this.success,
    this.error,
    this.nextCommands,
    this.sessionId,
  });
}