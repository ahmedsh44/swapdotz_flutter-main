import 'package:flutter/material.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MarketplaceProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await MarketplaceService.getOrCreateProfile(widget.userId);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: Text('Profile'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: Text('Profile'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Text(
            'Profile not found',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final isOwnProfile = widget.userId == MarketplaceService.currentUserId;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF1E1E1E),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildProfileHeader(),
            ),
            actions: [
              if (isOwnProfile)
                IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () {
                    // TODO: Navigate to edit profile screen
                  },
                ),
            ],
          ),
        ],
        body: Column(
          children: [
            // Stats Cards
            _buildStatsCards(),

            // Tab Bar
            Container(
              color: const Color(0xFF1E1E1E),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.blue,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[400],
                tabs: [
                  Tab(text: 'Listings'),
                  Tab(text: 'Sales'),
                  Tab(text: 'Purchases'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListingsTab(),
                  _buildSalesTab(),
                  _buildPurchasesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.3),
            const Color(0xFF1E1E1E),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blue,
              backgroundImage: _profile!.avatar != null
                  ? NetworkImage(_profile!.avatar!)
                  : null,
              child: _profile!.avatar == null
                  ? Text(
                      _profile!.displayName[0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            SizedBox(height: 12),

            // Name and Verification
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _profile!.displayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_profile!.isVerified) ...[
                  SizedBox(width: 8),
                  Icon(
                    Icons.verified,
                    color: Colors.blue,
                    size: 20,
                  ),
                ],
              ],
            ),

            // Bio
            if (_profile!.bio != null) ...[
              SizedBox(height: 8),
              Text(
                _profile!.bio!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Join Date
            SizedBox(height: 8),
            Text(
              'Joined ${_formatDate(_profile!.joinedAt)}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),

            // Badges
            if (_profile!.badges.isNotEmpty) ...[
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _profile!.badges.take(3).map((badge) {
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total Sales',
              '${_profile!.totalSales}',
              Icons.trending_up,
              Colors.green,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Purchases',
              '${_profile!.totalPurchases}',
              Icons.shopping_cart,
              Colors.blue,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Rating',
              _profile!.totalRatings > 0
                  ? _profile!.averageSellerRating.toStringAsFixed(1)
                  : 'N/A',
              Icons.star,
              Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildListingsTab() {
    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getUserListings(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data ?? [];

        if (listings.isEmpty) {
          return _buildEmptyState(
            'No listings',
            'This user hasn\'t listed any SwapDotz yet',
            Icons.list_alt,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: listings.length,
          itemBuilder: (context, index) {
            final listing = listings[index];
            return _buildListingCard(listing);
          },
        );
      },
    );
  }

  Widget _buildSalesTab() {
    return StreamBuilder<List<MarketplaceTransaction>>(
      stream: MarketplaceService.getUserSales(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data ?? [];

        if (transactions.isEmpty) {
          return _buildEmptyState(
            'No sales',
            'This user hasn\'t sold any SwapDotz yet',
            Icons.sell,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return _buildTransactionCard(transaction, isSellerView: true);
          },
        );
      },
    );
  }

  Widget _buildPurchasesTab() {
    return StreamBuilder<List<MarketplaceTransaction>>(
      stream: MarketplaceService.getUserPurchases(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data ?? [];

        if (transactions.isEmpty) {
          return _buildEmptyState(
            'No purchases',
            'This user hasn\'t purchased any SwapDotz yet',
            Icons.shopping_bag,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return _buildTransactionCard(transaction, isSellerView: false);
          },
        );
      },
    );
  }

  Widget _buildListingCard(Listing listing) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Image placeholder
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: listing.images.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      listing.images.first,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.nfc, color: Colors.grey[600]);
                      },
                    ),
                  )
                : Icon(Icons.nfc, color: Colors.grey[600]),
          ),
          SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  '\$${listing.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.remove_red_eye, color: Colors.grey[400], size: 14),
                    SizedBox(width: 4),
                    Text(
                      '${listing.views} views',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    SizedBox(width: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(listing.status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        listing.status.toString().split('.').last.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(MarketplaceTransaction transaction, {required bool isSellerView}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Token ID: ${transaction.tokenId}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '\$${transaction.finalPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isSellerView ? 'Buyer: ${transaction.buyerId}' : 'Seller: ${transaction.sellerId}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTransactionStatusColor(transaction.status),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  transaction.status.toString().split('.').last.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Completed: ${_formatDate(transaction.completedAt)}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          
          // Rating
          if (isSellerView && transaction.sellerRating != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(5, (index) {
                  return Icon(
                    index < transaction.sellerRating!.stars 
                        ? Icons.star 
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  );
                }),
                if (transaction.sellerRating!.comment != null) ...[
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"${transaction.sellerRating!.comment!}"',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ] else if (!isSellerView && transaction.buyerRating != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(5, (index) {
                  return Icon(
                    index < transaction.buyerRating!.stars 
                        ? Icons.star 
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  );
                }),
                if (transaction.buyerRating!.comment != null) ...[
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"${transaction.buyerRating!.comment!}"',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Colors.grey[600],
          ),
          SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(ListingStatus status) {
    switch (status) {
      case ListingStatus.active:
        return Colors.green;
      case ListingStatus.sold:
        return Colors.blue;
      case ListingStatus.expired:
        return Colors.orange;
      case ListingStatus.removed:
        return Colors.red;
      case ListingStatus.pending_transfer:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getTransactionStatusColor(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.completed:
        return Colors.green;
      case TransactionStatus.pending:
        return Colors.orange;
      case TransactionStatus.shipped:
        return Colors.blue;
      case TransactionStatus.disputed:
        return Colors.red;
      case TransactionStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return '${date.month}/${date.day}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }
} 