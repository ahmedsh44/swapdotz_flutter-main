import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a marketplace listing for a SwapDot
class Listing {
  final String id;
  final String tokenId;
  final String sellerId;
  final String sellerDisplayName;
  final String title;
  final String description;
  final double price; // In USD
  final List<String> images; // URLs to images
  final String condition; // "mint", "near_mint", "good", "fair", "poor"
  final List<String> tags; // Categories/tags
  final DateTime createdAt;
  final DateTime? expiresAt;
  final ListingStatus status;
  final ListingType type; // "auction", "fixed_price", "bundle"
  final Map<String, dynamic> metadata; // Additional custom data
  final int views;
  final int favorites;
  final String? location; // Optional location for local trades
  final bool shippingAvailable;
  final double? shippingCost;

  Listing({
    required this.id,
    required this.tokenId,
    required this.sellerId,
    required this.sellerDisplayName,
    required this.title,
    required this.description,
    required this.price,
    required this.images,
    required this.condition,
    required this.tags,
    required this.createdAt,
    this.expiresAt,
    required this.status,
    required this.type,
    required this.metadata,
    required this.views,
    required this.favorites,
    this.location,
    required this.shippingAvailable,
    this.shippingCost,
  });

  factory Listing.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Listing(
      id: doc.id,
      tokenId: data['tokenId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerDisplayName: data['sellerDisplayName'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0.0).toDouble(),
      images: List<String>.from(data['images'] ?? []),
      condition: data['condition'] ?? 'good',
      tags: List<String>.from(data['tags'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: data['expiresAt'] != null ? (data['expiresAt'] as Timestamp).toDate() : null,
      status: ListingStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => ListingStatus.active,
      ),
      type: ListingType.values.firstWhere(
        (e) => e.toString().split('.').last == data['type'],
        orElse: () => ListingType.fixed_price,
      ),
      metadata: data['metadata'] ?? {},
      views: data['views'] ?? 0,
      favorites: data['favorites'] ?? 0,
      location: data['location'],
      shippingAvailable: data['shippingAvailable'] ?? false,
      shippingCost: data['shippingCost']?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tokenId': tokenId,
      'sellerId': sellerId,
      'sellerDisplayName': sellerDisplayName,
      'title': title,
      'description': description,
      'price': price,
      'images': images,
      'condition': condition,
      'tags': tags,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'status': status.toString().split('.').last,
      'type': type.toString().split('.').last,
      'metadata': metadata,
      'views': views,
      'favorites': favorites,
      'location': location,
      'shippingAvailable': shippingAvailable,
      'shippingCost': shippingCost,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

enum ListingStatus {
  active,
  sold,
  expired,
  removed,
  pending_transfer,
}

enum ListingType {
  fixed_price,
  auction,
  bundle,
  trade_only,
}

/// Represents an offer on a listing
class Offer {
  final String id;
  final String listingId;
  final String buyerId;
  final String buyerDisplayName;
  final double amount;
  final String? message;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final OfferStatus status;
  final String? counterOfferReason;

  Offer({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.buyerDisplayName,
    required this.amount,
    this.message,
    required this.createdAt,
    this.expiresAt,
    required this.status,
    this.counterOfferReason,
  });

  factory Offer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Offer(
      id: doc.id,
      listingId: data['listingId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      buyerDisplayName: data['buyerDisplayName'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      message: data['message'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: data['expiresAt'] != null ? (data['expiresAt'] as Timestamp).toDate() : null,
      status: OfferStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => OfferStatus.pending,
      ),
      counterOfferReason: data['counterOfferReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'listingId': listingId,
      'buyerId': buyerId,
      'buyerDisplayName': buyerDisplayName,
      'amount': amount,
      'message': message,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'status': status.toString().split('.').last,
      'counterOfferReason': counterOfferReason,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

enum OfferStatus {
  pending,
  accepted,
  rejected,
  countered,
  expired,
  withdrawn,
}

/// Represents a completed marketplace transaction
class MarketplaceTransaction {
  final String id;
  final String listingId;
  final String tokenId;
  final String sellerId;
  final String buyerId;
  final double finalPrice;
  final double platformFee;
  final double shippingCost;
  final DateTime completedAt;
  final TransactionStatus status;
  final String? transferSessionId; // Links to secure transfer
  final String? notes;
  final TransactionRating? sellerRating;
  final TransactionRating? buyerRating;

  MarketplaceTransaction({
    required this.id,
    required this.listingId,
    required this.tokenId,
    required this.sellerId,
    required this.buyerId,
    required this.finalPrice,
    required this.platformFee,
    required this.shippingCost,
    required this.completedAt,
    required this.status,
    this.transferSessionId,
    this.notes,
    this.sellerRating,
    this.buyerRating,
  });

  factory MarketplaceTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MarketplaceTransaction(
      id: doc.id,
      listingId: data['listingId'] ?? '',
      tokenId: data['tokenId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      finalPrice: (data['finalPrice'] ?? 0.0).toDouble(),
      platformFee: (data['platformFee'] ?? 0.0).toDouble(),
      shippingCost: (data['shippingCost'] ?? 0.0).toDouble(),
      completedAt: (data['completedAt'] as Timestamp).toDate(),
      status: TransactionStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => TransactionStatus.pending,
      ),
      transferSessionId: data['transferSessionId'],
      notes: data['notes'],
      sellerRating: data['sellerRating'] != null
          ? TransactionRating.fromMap(data['sellerRating'])
          : null,
      buyerRating: data['buyerRating'] != null
          ? TransactionRating.fromMap(data['buyerRating'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'listingId': listingId,
      'tokenId': tokenId,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'finalPrice': finalPrice,
      'platformFee': platformFee,
      'shippingCost': shippingCost,
      'completedAt': Timestamp.fromDate(completedAt),
      'status': status.toString().split('.').last,
      'transferSessionId': transferSessionId,
      'notes': notes,
      'sellerRating': sellerRating?.toMap(),
      'buyerRating': buyerRating?.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

enum TransactionStatus {
  pending,
  payment_confirmed,
  shipped,
  delivered,
  completed,
  disputed,
  cancelled,
}

/// Rating given in a transaction
class TransactionRating {
  final int stars; // 1-5
  final String? comment;
  final DateTime createdAt;

  TransactionRating({
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  factory TransactionRating.fromMap(Map<String, dynamic> data) {
    return TransactionRating(
      stars: data['stars'] ?? 0,
      comment: data['comment'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stars': stars,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// User marketplace profile
class MarketplaceProfile {
  final String userId;
  final String displayName;
  final String? avatar;
  final String? bio;
  final DateTime joinedAt;
  final int totalSales;
  final int totalPurchases;
  final double averageSellerRating;
  final double averageBuyerRating;
  final int totalRatings;
  final bool isVerified;
  final List<String> badges; // Achievement badges
  final Map<String, dynamic> preferences;

  MarketplaceProfile({
    required this.userId,
    required this.displayName,
    this.avatar,
    this.bio,
    required this.joinedAt,
    required this.totalSales,
    required this.totalPurchases,
    required this.averageSellerRating,
    required this.averageBuyerRating,
    required this.totalRatings,
    required this.isVerified,
    required this.badges,
    required this.preferences,
  });

  factory MarketplaceProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MarketplaceProfile(
      userId: doc.id,
      displayName: data['displayName'] ?? '',
      avatar: data['avatar'],
      bio: data['bio'],
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      totalSales: data['totalSales'] ?? 0,
      totalPurchases: data['totalPurchases'] ?? 0,
      averageSellerRating: (data['averageSellerRating'] ?? 0.0).toDouble(),
      averageBuyerRating: (data['averageBuyerRating'] ?? 0.0).toDouble(),
      totalRatings: data['totalRatings'] ?? 0,
      isVerified: data['isVerified'] ?? false,
      badges: List<String>.from(data['badges'] ?? []),
      preferences: data['preferences'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'avatar': avatar,
      'bio': bio,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'totalSales': totalSales,
      'totalPurchases': totalPurchases,
      'averageSellerRating': averageSellerRating,
      'averageBuyerRating': averageBuyerRating,
      'totalRatings': totalRatings,
      'isVerified': isVerified,
      'badges': badges,
      'preferences': preferences,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

/// Search filters for marketplace
class MarketplaceFilters {
  final double? minPrice;
  final double? maxPrice;
  final List<String>? conditions;
  final List<String>? tags;
  final String? location;
  final bool? shippingAvailable;
  final ListingType? listingType;
  final String? sortBy; // "price_asc", "price_desc", "newest", "oldest", "popularity"

  MarketplaceFilters({
    this.minPrice,
    this.maxPrice,
    this.conditions,
    this.tags,
    this.location,
    this.shippingAvailable,
    this.listingType,
    this.sortBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'conditions': conditions,
      'tags': tags,
      'location': location,
      'shippingAvailable': shippingAvailable,
      'listingType': listingType?.toString().split('.').last,
      'sortBy': sortBy,
    };
  }
} 