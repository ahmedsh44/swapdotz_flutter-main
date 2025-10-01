/// Model representing data stored on an NFC token
class TokenData {
  final String? owner;
  final String? key;
  final String? previousOwner;
  final DateTime? initializedTime;
  final DateTime? claimedTime;
  final bool hasActiveTransfer;
  final String? transferFrom;
  final DateTime? transferTime;
  final String? rarity;
  
  TokenData({
    this.owner,
    this.key,
    this.previousOwner,
    this.initializedTime,
    this.claimedTime,
    this.hasActiveTransfer = false,
    this.transferFrom,
    this.transferTime,
    this.rarity,
  });
  
  /// Parse token data from string format
  factory TokenData.fromString(String data) {
    String? owner;
    String? key;
    String? previousOwner;
    DateTime? initializedTime;
    DateTime? claimedTime;
    bool hasActiveTransfer = false;
    String? transferFrom;
    DateTime? transferTime;
    String? rarity;
    
    // Parse key-value pairs
    final parts = data.split(';');
    for (final part in parts) {
      if (part.contains(':')) {
        final keyValue = part.split(':');
        final k = keyValue[0];
        final v = keyValue[1];
        
        switch (k) {
          case 'owner':
            owner = v;
            break;
          case 'key':
            key = v;
            break;
          case 'prev':
            previousOwner = v;
            break;
          case 'initialized':
            initializedTime = DateTime.fromMillisecondsSinceEpoch(int.parse(v));
            break;
          case 'claimed':
            claimedTime = DateTime.fromMillisecondsSinceEpoch(int.parse(v));
            break;
          case 'transfer':
            hasActiveTransfer = v == 'active';
            break;
          case 'from':
            transferFrom = v;
            break;
          case 'time':
            if (hasActiveTransfer) {
              transferTime = DateTime.fromMillisecondsSinceEpoch(int.parse(v));
            }
            break;
          case 'rarity':
            rarity = v;
            break;
        }
      }
    }
    
    return TokenData(
      owner: owner,
      key: key,
      previousOwner: previousOwner,
      initializedTime: initializedTime,
      claimedTime: claimedTime,
      hasActiveTransfer: hasActiveTransfer,
      transferFrom: transferFrom,
      transferTime: transferTime,
      rarity: rarity,
    );
  }
  
  /// Check if token is initialized
  bool get isInitialized => key != null && key!.isNotEmpty;
  
  /// Check if current user owns this token
  bool isOwnedBy(String user) => owner == user;
  
  /// Check if transfer is from a specific user
  bool hasTransferFrom(String user) => hasActiveTransfer && transferFrom == user;
  
  /// Convert back to string format for writing
  @override
  String toString() {
    final parts = <String>[];
    
    if (owner != null) parts.add('owner:$owner');
    if (key != null) parts.add('key:$key');
    if (previousOwner != null) parts.add('prev:$previousOwner');
    if (initializedTime != null) parts.add('initialized:${initializedTime!.millisecondsSinceEpoch}');
    if (claimedTime != null) parts.add('claimed:${claimedTime!.millisecondsSinceEpoch}');
    if (hasActiveTransfer) {
      parts.add('transfer:active');
      if (transferFrom != null) parts.add('from:$transferFrom');
      if (transferTime != null) parts.add('time:${transferTime!.millisecondsSinceEpoch}');
    }
    if (rarity != null) parts.add('rarity:$rarity');
    
    return parts.join(';');
  }
} 