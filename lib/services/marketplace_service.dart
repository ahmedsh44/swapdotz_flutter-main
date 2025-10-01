import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/marketplace_models.dart';

class MarketplaceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Collections
  static const String _listingsCollection = 'marketplace_listings';
  static const String _offersCollection = 'marketplace_offers';
  static const String _transactionsCollection = 'marketplace_transactions';
  static const String _profilesCollection = 'marketplace_profiles';

  /// Get current user ID
  static String? get currentUserId => _auth.currentUser?.uid;

  /// Create a new listing
  static Future<String> createListing({
    required String tokenId,
    required String title,
    required String description,
    required double price,
    required List<String> images,
    required String condition,
    required List<String> tags,
    required ListingType type,
    String? location,
    bool shippingAvailable = false,
    double? shippingCost,
    DateTime? expiresAt,
    Map<String, dynamic>? metadata,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    // CRITICAL: Verify user owns the token with FRESH data
    final tokenDoc = await _firestore.collection('tokens').doc(tokenId)
        .get(const GetOptions(source: Source.server));
    if (!tokenDoc.exists) {
      throw Exception('Token not found');
    }
    
    final tokenData = tokenDoc.data()!;
    // Check both fields for ownership (ownerUid is primary, current_owner_id is legacy)
    final actualOwner = tokenData['ownerUid'] ?? tokenData['current_owner_id'];
    if (actualOwner != currentUserId) {
      throw Exception('You do not own this token');
    }

    // Check if token is already listed (FRESH data to prevent double-listing)
    final existingListing = await _firestore
        .collection(_listingsCollection)
        .where('tokenId', isEqualTo: tokenId)
        .where('status', isEqualTo: 'active')
        .get(const GetOptions(source: Source.server));
    
    if (existingListing.docs.isNotEmpty) {
      throw Exception('Token is already listed in the marketplace');
    }

    // Extract token metadata from Firebase
    final tokenMetadata = tokenData['metadata'] as Map<String, dynamic>? ?? {};
    final tokenName = tokenMetadata['name'] ?? 'Unknown Token';
    final tokenSeries = tokenMetadata['series'] ?? 'Unknown Series';
    final tokenRarity = tokenMetadata['rarity'] ?? 'common';
    
    // Get user profile
    final profile = await getOrCreateProfile(currentUserId!);

    // Merge token metadata with any custom metadata provided
    final enrichedMetadata = {
      'tokenName': tokenName,
      'tokenSeries': tokenSeries,
      'tokenRarity': tokenRarity,
      ...?metadata, // Spread any additional metadata if provided
    };

    final listing = Listing(
      id: '', // Will be set by Firestore
      tokenId: tokenId,
      sellerId: currentUserId!,
      sellerDisplayName: profile.displayName,
      title: title,
      description: description,
      price: price,
      images: images,
      condition: condition,
      tags: tags,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      status: ListingStatus.active,
      type: type,
      metadata: enrichedMetadata,
      views: 0,
      favorites: 0,
      location: location,
      shippingAvailable: shippingAvailable,
      shippingCost: shippingCost,
    );

    final docRef = await _firestore
        .collection(_listingsCollection)
        .add(listing.toFirestore());

    return docRef.id;
  }

  /// Get active listings with optional filters
  static Stream<List<Listing>> getListings({
    MarketplaceFilters? filters,
    int limit = 20,
  }) {
    // Start with a simple query without ordering to avoid index issues
    Query query = _firestore
        .collection(_listingsCollection)
        .where('status', isEqualTo: 'active')
        .limit(limit);

    // Apply filters
    if (filters != null) {
      if (filters.minPrice != null) {
        query = query.where('price', isGreaterThanOrEqualTo: filters.minPrice);
      }
      if (filters.maxPrice != null) {
        query = query.where('price', isLessThanOrEqualTo: filters.maxPrice);
      }
      if (filters.conditions != null && filters.conditions!.isNotEmpty) {
        query = query.where('condition', whereIn: filters.conditions);
      }
      if (filters.listingType != null) {
        query = query.where('type', isEqualTo: filters.listingType.toString().split('.').last);
      }
      if (filters.tags != null && filters.tags!.isNotEmpty) {
        query = query.where('tags', arrayContainsAny: filters.tags);
      }
      if (filters.location != null && filters.location!.isNotEmpty) {
        query = query.where('location', isEqualTo: filters.location);
      }
      if (filters.shippingAvailable != null) {
        query = query.where('shippingAvailable', isEqualTo: filters.shippingAvailable);
      }
    }

    // Remove the orderBy for now to avoid index issues
    // query = query.orderBy('createdAt', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Listing.fromFirestore(doc))
          .toList();
    }).handleError((error) {
      print('Error in getListings stream (collection might be empty): $error');
      return <Listing>[];
    });
  }

  /// Get a specific listing by ID
  static Future<Listing?> getListing(String listingId) async {
    final doc = await _firestore.collection(_listingsCollection).doc(listingId).get();
    if (!doc.exists) return null;
    return Listing.fromFirestore(doc);
  }

  /// Get user's own listings
  static Stream<List<Listing>> getUserListings(String userId) {
    return _firestore
        .collection(_listingsCollection)
        .where('sellerId', isEqualTo: userId)
        // Removed orderBy to avoid index requirements
        .snapshots()
        .map((snapshot) {
      // Filter out removed and sold listings, then sort locally
      final listings = snapshot.docs
          .map((doc) => Listing.fromFirestore(doc))
          .where((listing) => listing.status == ListingStatus.active) // Only show active listings
          .toList();
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    }).handleError((error) {
      print('Error in getUserListings stream (collection might be empty): $error');
      return <Listing>[]; // Return empty list on error
    });
  }

  /// Get ALL user's listings including sold and removed (for history)
  static Stream<List<Listing>> getUserListingsHistory(String userId) {
    return _firestore
        .collection(_listingsCollection)
        .where('sellerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs.map((doc) => Listing.fromFirestore(doc)).toList();
      // Sort by date, newest first
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    }).handleError((error) {
      print('Error in getUserListingsHistory stream: $error');
      return <Listing>[];
    });
  }

  /// Update listing views
  static Future<void> incrementListingViews(String listingId) async {
    try {
      await _firestore.collection(_listingsCollection).doc(listingId).update({
        'views': FieldValue.increment(1),
      });
    } catch (e) {
      // Silently fail if user doesn't have permission to update views
      // This is expected for anonymous users or non-sellers
      print('Could not update views (expected for non-sellers): $e');
    }
  }

  /// Toggle favorite status
  static Future<void> toggleFavorite(String listingId, bool isFavorite) async {
    if (currentUserId == null) return;

    // Update listing favorites count
    await _firestore.collection(_listingsCollection).doc(listingId).update({
      'favorites': FieldValue.increment(isFavorite ? 1 : -1),
    });

    // Update user's favorites list
    final userFavoritesRef = _firestore
        .collection('user_favorites')
        .doc(currentUserId);

    if (isFavorite) {
      await userFavoritesRef.set({
        'listings': FieldValue.arrayUnion([listingId])
      }, SetOptions(merge: true));
    } else {
      await userFavoritesRef.update({
        'listings': FieldValue.arrayRemove([listingId])
      });
    }
  }

  /// Get user's favorite listings
  static Future<List<String>> getUserFavorites() async {
    if (currentUserId == null) return [];
    
    try {
      final doc = await _firestore
          .collection('user_favorites')
          .doc(currentUserId)
          .get();
      
      if (!doc.exists) return [];
      
      final data = doc.data();
      if (data == null || !data.containsKey('listings')) return [];
      
      return List<String>.from(data['listings'] ?? []);
    } catch (e) {
      print('Error getting user favorites: $e');
      return [];
    }
  }

  /// Make an offer on a listing
  static Future<String> makeOffer({
    required String listingId,
    required double amount,
    String? message,
    DateTime? expiresAt,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    final listing = await getListing(listingId);
    if (listing == null) throw Exception('Listing not found');
    if (listing.sellerId == currentUserId) throw Exception('Cannot make offer on your own listing');

    final profile = await getOrCreateProfile(currentUserId!);

    final offer = Offer(
      id: '', // Will be set by Firestore
      listingId: listingId,
      buyerId: currentUserId!,
      buyerDisplayName: profile.displayName,
      amount: amount,
      message: message,
      createdAt: DateTime.now(),
      expiresAt: expiresAt ?? DateTime.now().add(Duration(days: 7)),
      status: OfferStatus.pending,
    );

    final docRef = await _firestore
        .collection(_offersCollection)
        .add(offer.toFirestore());

    return docRef.id;
  }

  /// Get offers for a listing
  static Stream<List<Offer>> getListingOffers(String listingId) {
    return _firestore
        .collection(_offersCollection)
        .where('listingId', isEqualTo: listingId)
        // Removed orderBy to avoid index requirements
        .snapshots()
        .map((snapshot) {
      // Sort locally instead
      final offers = snapshot.docs.map((doc) => Offer.fromFirestore(doc)).toList();
      offers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return offers;
    });
  }

  /// Accept an offer
  static Future<void> acceptOffer(String offerId) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    // Use Cloud Function for atomic transaction
    final result = await _functions.httpsCallable('acceptMarketplaceOffer').call({
      'offerId': offerId,
    });

    if (result.data['success'] != true) {
      throw Exception(result.data['error'] ?? 'Failed to accept offer');
    }
  }

  /// Reject an offer
  static Future<void> rejectOffer(String offerId, {String? reason}) async {
    await _firestore.collection(_offersCollection).doc(offerId).update({
      'status': OfferStatus.rejected.toString().split('.').last,
      'counterOfferReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get or create user marketplace profile
  static Future<MarketplaceProfile> getOrCreateProfile(String userId) async {
    try {
      final doc = await _firestore.collection(_profilesCollection).doc(userId).get();
    
    if (doc.exists) {
      return MarketplaceProfile.fromFirestore(doc);
    }

    // Create new profile
    final profile = MarketplaceProfile(
      userId: userId,
      displayName: _auth.currentUser?.displayName ?? 'User ${userId.substring(0, 6)}',
      joinedAt: DateTime.now(),
      totalSales: 0,
      totalPurchases: 0,
      averageSellerRating: 0.0,
      averageBuyerRating: 0.0,
      totalRatings: 0,
      isVerified: false,
      badges: [],
      preferences: {},
    );

    await _firestore.collection(_profilesCollection).doc(userId).set(profile.toFirestore());
    return profile;
    } catch (e) {
      print('Error getting/creating marketplace profile: $e');
      // Return a basic profile if Firebase fails
      return MarketplaceProfile(
        userId: userId,
        displayName: 'User ${userId.substring(0, 6)}',
        joinedAt: DateTime.now(),
        totalSales: 0,
        totalPurchases: 0,
        averageSellerRating: 0.0,
        averageBuyerRating: 0.0,
        totalRatings: 0,
        isVerified: false,
        badges: [],
        preferences: {},
      );
    }
  }

  /// Search listings by text
  static Future<List<Listing>> searchListings({
    required String query,
    MarketplaceFilters? filters,
    int limit = 20,
  }) async {
    // Simplified search to avoid index requirements
    // Fetch all active listings and filter in memory
    
    final queryLower = query.toLowerCase();
    
    // Get all active listings (without complex queries to avoid indexes)
    final allListings = await _firestore
        .collection(_listingsCollection)
        .where('status', isEqualTo: 'active')
        .limit(100) // Fetch more to have enough for filtering
        .get();
    
    // Filter in memory
    final results = allListings.docs
        .map((doc) => Listing.fromFirestore(doc))
        .where((listing) {
          // Search in title
          if (listing.title.toLowerCase().contains(queryLower)) {
            return true;
          }
          // Search in description
          if (listing.description.toLowerCase().contains(queryLower)) {
            return true;
          }
          // Search in tags
          if (listing.tags.any((tag) => tag.toLowerCase().contains(queryLower))) {
            return true;
          }
          return false;
        })
        .take(limit)
        .toList();
    
    // Apply additional filters if provided
    if (filters != null) {
      return results.where((listing) {
        if (filters.minPrice != null && listing.price < filters.minPrice!) {
          return false;
        }
        if (filters.maxPrice != null && listing.price > filters.maxPrice!) {
          return false;
        }
        if (filters.conditions != null && filters.conditions!.isNotEmpty &&
            !filters.conditions!.contains(listing.condition)) {
          return false;
        }
        if (filters.listingType != null && listing.type != filters.listingType) {
          return false;
        }
        if (filters.location != null && filters.location!.isNotEmpty &&
            listing.location != filters.location) {
          return false;
        }
        if (filters.shippingAvailable != null && 
            listing.shippingAvailable != filters.shippingAvailable) {
          return false;
        }
        return true;
      }).toList();
    }
    
    return results;
  }

  /// Get user's purchase history
  static Stream<List<MarketplaceTransaction>> getUserPurchases(String userId) {
    return _firestore
        .collection(_transactionsCollection)
        .where('buyerId', isEqualTo: userId)
        // Removed orderBy to avoid index requirements
        .snapshots()
        .map((snapshot) {
      // Sort locally instead
      final transactions = snapshot.docs.map((doc) => MarketplaceTransaction.fromFirestore(doc)).toList();
      transactions.sort((a, b) => b.completedAt?.compareTo(a.completedAt ?? DateTime(0)) ?? 0);
      return transactions;
    });
  }

  /// Get user's sales history
  static Stream<List<MarketplaceTransaction>> getUserSales(String userId) {
    return _firestore
        .collection(_transactionsCollection)
        .where('sellerId', isEqualTo: userId)
        // Removed orderBy to avoid index requirements
        .snapshots()
        .map((snapshot) {
      // Sort locally instead
      final transactions = snapshot.docs.map((doc) => MarketplaceTransaction.fromFirestore(doc)).toList();
      transactions.sort((a, b) => b.completedAt?.compareTo(a.completedAt ?? DateTime(0)) ?? 0);
      return transactions;
    });
  }

  /// Complete a transaction (called after successful transfer)
  static Future<void> completeTransaction({
    required String transactionId,
    String? notes,
  }) async {
    await _firestore.collection(_transactionsCollection).doc(transactionId).update({
      'status': TransactionStatus.completed.toString().split('.').last,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rate a transaction
  static Future<void> rateTransaction({
    required String transactionId,
    required int stars,
    String? comment,
    required bool isSellerRating, // true if rating the seller, false if rating the buyer
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    final rating = TransactionRating(
      stars: stars,
      comment: comment,
      createdAt: DateTime.now(),
    );

    final field = isSellerRating ? 'sellerRating' : 'buyerRating';
    
    await _firestore.collection(_transactionsCollection).doc(transactionId).update({
      field: rating.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update user profile ratings (this should ideally be done in a Cloud Function)
    await _updateUserRatings(transactionId, isSellerRating);
  }

  /// Update user ratings after a new rating is added
  static Future<void> _updateUserRatings(String transactionId, bool isSellerRating) async {
    // Get the transaction
    final transactionDoc = await _firestore.collection(_transactionsCollection).doc(transactionId).get();
    if (!transactionDoc.exists) return;

    final transaction = MarketplaceTransaction.fromFirestore(transactionDoc);
    final userId = isSellerRating ? transaction.sellerId : transaction.buyerId;
    
    // Get all transactions for this user as seller/buyer
    final userTransactions = await _firestore
        .collection(_transactionsCollection)
        .where(isSellerRating ? 'sellerId' : 'buyerId', isEqualTo: userId)
        .get();

    // Calculate new average rating
    double totalRating = 0;
    int ratingCount = 0;

    for (final doc in userTransactions.docs) {
      final t = MarketplaceTransaction.fromFirestore(doc);
      final rating = isSellerRating ? t.sellerRating : t.buyerRating;
      if (rating != null) {
        totalRating += rating.stars;
        ratingCount++;
      }
    }

    if (ratingCount > 0) {
      final averageRating = totalRating / ratingCount;
      final field = isSellerRating ? 'averageSellerRating' : 'averageBuyerRating';
      
      await _firestore.collection(_profilesCollection).doc(userId).update({
        field: averageRating,
        'totalRatings': ratingCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Update an existing listing
  static Future<void> updateListing({
    required String listingId,
    required String title,
    required String description,
    required double price,
    required String condition,
    required List<String> tags,
    required ListingType type,
    String? location,
    bool shippingAvailable = false,
    double? shippingCost,
  }) async {
    print('DEBUG: updateListing called for listing $listingId');
    print('DEBUG: Current user ID: $currentUserId');
    
    if (currentUserId == null) throw Exception('User not authenticated');

    // Verify ownership
    final listing = await getListing(listingId);
    if (listing == null) throw Exception('Listing not found');
    
    print('DEBUG: Listing seller ID: ${listing.sellerId}');
    print('DEBUG: Is owner: ${listing.sellerId == currentUserId}');
    
    if (listing.sellerId != currentUserId) throw Exception('You can only edit your own listings');

    final updateData = {
      'title': title,
      'description': description,
      'price': price,
      'condition': condition,
      'tags': tags,
      'type': type.toString().split('.').last,
      'location': location,
      'shippingAvailable': shippingAvailable,
      'shippingCost': shippingCost,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    print('DEBUG: Updating with data: $updateData');
    
    await _firestore.collection(_listingsCollection).doc(listingId).update(updateData);
    
    print('DEBUG: Update completed successfully');
  }

  /// Remove a listing
  static Future<void> removeListing(String listingId) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    final listing = await getListing(listingId);
    if (listing == null) throw Exception('Listing not found');
    if (listing.sellerId != currentUserId) throw Exception('You can only remove your own listings');

    // Use a batch write for atomic operations
    final batch = _firestore.batch();
    
    // 1. Update the listing status to removed
    batch.update(_firestore.collection(_listingsCollection).doc(listingId), {
      'status': ListingStatus.removed.toString().split('.').last,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    // 2. We can't remove from all users' favorites due to permissions,
    // but the UI will handle showing removed listings appropriately
    // Users can manually remove them from their watchlist
    
    // 3. Cancel all pending offers for this listing (only if we have permission)
    try {
      final offersQuery = await _firestore
          .collection(_offersCollection)
          .where('listingId', isEqualTo: listingId)
          .where('status', isEqualTo: OfferStatus.pending.toString().split('.').last)
          .get();
      
      for (final doc in offersQuery.docs) {
        batch.update(doc.reference, {
          'status': OfferStatus.withdrawn.toString().split('.').last,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // If we can't access offers, that's okay - just update the listing status
      print('Could not cancel offers (may not have permission): $e');
    }
    
    // Commit all changes atomically
    await batch.commit();
    
    print('DEBUG: Listing $listingId removed successfully');
  }

  /// Get trending tags from active listings
  static Future<List<String>> getTrendingTags({int limit = 10}) async {
    try {
      // Simplified query without ordering to avoid permission issues
      final listings = await _firestore
          .collection(_listingsCollection)
          .where('status', isEqualTo: 'active')
          .limit(100)
          .get();

      // If no listings exist, return empty list (no error)
      if (listings.docs.isEmpty) {
        print('No active listings found - returning empty trending tags');
        return [];
      }

      final tagCounts = <String, int>{};
      for (final doc in listings.docs) {
        final listing = Listing.fromFirestore(doc);
        for (final tag in listing.tags) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }

      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sortedTags.take(limit).map((e) => e.key).toList();
    } catch (e) {
      print('Error loading trending tags (collection might be empty): $e');
      return []; // Return empty list instead of throwing error
    }
  }

  /// Get user's sold listings
  static Stream<List<Listing>> getUserSoldListings(String userId) {
    return _firestore
        .collection(_listingsCollection)
        .where('sellerId', isEqualTo: userId)
        .where('status', isEqualTo: 'sold')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Listing.fromFirestore(doc)).toList();
    });
  }

  /// Get user's purchased listings
  static Stream<List<Listing>> getUserPurchasedListings(String userId) {
    return _firestore
        .collection(_listingsCollection)
        .where('buyerId', isEqualTo: userId)
        .where('status', isEqualTo: 'sold')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Listing.fromFirestore(doc)).toList();
    });
  }
} 