/// Transfer session model for NFC token transfers
class TransferSession {
  final String sessionId;
  final String tokenUid;
  final String fromUserId;
  final String? toUserId;
  final DateTime expiresAt;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic>? challengeData;

  TransferSession({
    required this.sessionId,
    required this.tokenUid,
    required this.fromUserId,
    this.toUserId,
    required this.expiresAt,
    required this.status,
    required this.createdAt,
    this.challengeData,
  });

  factory TransferSession.fromMap(Map<String, dynamic> data) {
    return TransferSession(
      sessionId: data['session_id'] ?? '',
      tokenUid: data['token_uid'] ?? '',
      fromUserId: data['from_user_id'] ?? '',
      toUserId: data['to_user_id'],
      expiresAt: data['expires_at']?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'pending',
      createdAt: data['created_at']?.toDate() ?? DateTime.now(),
      challengeData: data['challenge_data'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'token_uid': tokenUid,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'expires_at': expiresAt,
      'status': status,
      'created_at': createdAt,
      'challenge_data': challengeData,
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == 'pending' && !isExpired;
  bool get isCompleted => status == 'completed';
} 