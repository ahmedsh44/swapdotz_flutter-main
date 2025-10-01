class SellerVerificationSession {
  final String sessionId;
  final String tokenId;
  final String sellerId;
  final String buyerId;
  final String listingId;
  final String paymentIntentId;
  final double amount;
  final DateTime createdAt;
  final DateTime expiresAt; // 30 days from creation
  final SellerVerificationStatus status;
  final DateTime? nfcVerifiedAt;
  final DateTime? completedAt;
  final Map<String, dynamic>? metadata;

  SellerVerificationSession({
    required this.sessionId,
    required this.tokenId,
    required this.sellerId,
    required this.buyerId,
    required this.listingId,
    required this.paymentIntentId,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    this.nfcVerifiedAt,
    this.completedAt,
    this.metadata,
  });

  factory SellerVerificationSession.fromFirestore(Map<String, dynamic> data) {
    return SellerVerificationSession(
      sessionId: data['session_id'],
      tokenId: data['token_id'],
      sellerId: data['seller_id'],
      buyerId: data['buyer_id'],
      listingId: data['listing_id'],
      paymentIntentId: data['payment_intent_id'],
      amount: (data['amount'] as num).toDouble(),
      createdAt: DateTime.parse(data['created_at']),
      expiresAt: DateTime.parse(data['expires_at']),
      status: SellerVerificationStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
      ),
      nfcVerifiedAt: data['nfc_verified_at'] != null 
          ? DateTime.parse(data['nfc_verified_at']) 
          : null,
      completedAt: data['completed_at'] != null 
          ? DateTime.parse(data['completed_at']) 
          : null,
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'session_id': sessionId,
      'token_id': tokenId,
      'seller_id': sellerId,
      'buyer_id': buyerId,
      'listing_id': listingId,
      'payment_intent_id': paymentIntentId,
      'amount': amount,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'status': status.toString().split('.').last,
      'nfc_verified_at': nfcVerifiedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isNfcVerified => nfcVerifiedAt != null;
  bool get isCompleted => status == SellerVerificationStatus.completed;
  
  Duration get timeRemaining {
    if (isExpired) return Duration.zero;
    return expiresAt.difference(DateTime.now());
  }

  String get timeRemainingText {
    final remaining = timeRemaining;
    if (remaining == Duration.zero) return 'Expired';
    
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    
    if (days > 0) {
      return '$days day${days != 1 ? 's' : ''}, $hours hour${hours != 1 ? 's' : ''} remaining';
    } else {
      return '$hours hour${hours != 1 ? 's' : ''} remaining';
    }
  }

  SellerVerificationSession copyWith({
    SellerVerificationStatus? status,
    DateTime? nfcVerifiedAt,
    DateTime? completedAt,
    Map<String, dynamic>? metadata,
  }) {
    return SellerVerificationSession(
      sessionId: sessionId,
      tokenId: tokenId,
      sellerId: sellerId,
      buyerId: buyerId,
      listingId: listingId,
      paymentIntentId: paymentIntentId,
      amount: amount,
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      nfcVerifiedAt: nfcVerifiedAt ?? this.nfcVerifiedAt,
      completedAt: completedAt ?? this.completedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum SellerVerificationStatus {
  pending_nfc_scan,    // Waiting for seller to scan SwapDot with NFC
  nfc_verified,        // Seller has scanned and verified ownership
  completed,           // Transaction completed, token transferred
  expired,             // Session expired (30 days passed)
  cancelled,           // Transaction was cancelled or refunded
}

extension SellerVerificationStatusExtension on SellerVerificationStatus {
  String get displayName {
    switch (this) {
      case SellerVerificationStatus.pending_nfc_scan:
        return 'Pending NFC Verification';
      case SellerVerificationStatus.nfc_verified:
        return 'NFC Verified - Ready to Ship';
      case SellerVerificationStatus.completed:
        return 'Completed';
      case SellerVerificationStatus.expired:
        return 'Expired';
      case SellerVerificationStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get description {
    switch (this) {
      case SellerVerificationStatus.pending_nfc_scan:
        return 'Seller must scan the SwapDot with NFC to verify they have it';
      case SellerVerificationStatus.nfc_verified:
        return 'Seller has verified ownership. Safe to ship or transfer.';
      case SellerVerificationStatus.completed:
        return 'Transaction completed successfully';
      case SellerVerificationStatus.expired:
        return 'Verification period expired (30 days)';
      case SellerVerificationStatus.cancelled:
        return 'Transaction was cancelled or refunded';
    }
  }

  bool get requiresAction {
    return this == SellerVerificationStatus.pending_nfc_scan;
  }
} 