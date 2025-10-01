import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';
import 'listing_detail_screen.dart';
import 'create_listing_screen.dart';
import 'user_profile_screen.dart';
import 'seller_verification_screen.dart';
import 'buyer_verification_screen.dart';
import 'watchlist_screen.dart';
import 'my_sales_screen.dart'; // Added import for MySalesScreen

class MarketplaceScreen extends StatefulWidget {
  @override
  _MarketplaceScreenState createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  MarketplaceFilters _filters = MarketplaceFilters();
  List<String> _trendingTags = [];
  bool _isSearching = false;
  List<Listing> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _ensureAuthAndLoadData();
  }
  
  Future<void> _ensureAuthAndLoadData() async {
    // Ensure user is authenticated before loading data
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (_) {}
    }
    try {
      await _loadTrendingTags();
    } catch (e) {
      // Swallow permission errors so UI loads
      debugPrint('Marketplace init error: $e');
      setState(() {});
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrendingTags() async {
    try {
      final tags = await MarketplaceService.getTrendingTags();
      setState(() {
        _trendingTags = tags;
      });
    } catch (e) {
      debugPrint('Error loading trending tags: $e');
    }
  }

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await MarketplaceService.searchListings(
        query: _searchController.text.trim(),
        filters: _filters,
      );
      
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFiltersBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is authenticated
    final currentUserId = MarketplaceService.currentUserId;
    
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: FirebaseAuth.instance.currentUser == null
          ? Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1E1E1E),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
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
              ),
              title: Text(
                'SwapDotz Store',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.favorite),
                color: Colors.red,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WatchlistScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.person),
                onPressed: MarketplaceService.currentUserId == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: MarketplaceService.currentUserId!,
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            // Search Bar
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search SwapDotz...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.tune, color: Colors.white),
                      onPressed: _showFiltersBottomSheet,
                    ),
                  ),
                ],
              ),
            ),

            // Trending Tags
            if (_trendingTags.isNotEmpty)
              Container(
                height: 50,
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _trendingTags.length,
                  itemBuilder: (context, index) {
                    final tag = _trendingTags[index];
                    return Container(
                      margin: EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          '#$tag',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        backgroundColor: Colors.grey[800],
                        onPressed: () {
                          _searchController.text = tag;
                          _performSearch();
                        },
                      ),
                    );
                  },
                ),
              ),

            // Tab Bar
            Container(
              color: const Color(0xFF1E1E1E),
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.blue,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[400],
                isScrollable: true,
                tabs: [
                  Tab(text: 'Browse'),
                  Tab(text: 'Trending'),
                  Tab(text: 'My Listings'),
                  Tab(text: 'My Sales'),
                  Tab(text: 'My Purchases'),
                  Tab(text: 'Watchlist'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBrowseTab(),
                  _buildTrendingTab(),
                  _buildMyListingsTab(),
                  _buildMySalesTab(),
                  _buildMyPurchasesTab(),
                  _buildWatchlistTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: currentUserId != null ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => CreateListingScreen()),
          );
        },
        backgroundColor: Colors.blue,
        icon: Icon(Icons.add),
        label: Text('Sell'),
      ) : null,
    );
  }

  Widget _buildNotAuthenticatedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storefront,
            size: 80,
            color: Colors.grey[600],
          ),
          SizedBox(height: 24),
          Text(
            'Welcome to SwapDotz Store!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Please return to the main screen to authenticate\nand access the marketplace.',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Back to Main Screen',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseTab() {
    if (_searchController.text.isNotEmpty) {
      return _buildSearchResults();
    }

    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getListings(filters: _filters),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading listings: ${snapshot.error}',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        final listings = snapshot.data ?? [];

        if (listings.isEmpty) {
          return _buildEmptyState('No listings found', 'Try adjusting your filters');
        }

        return _buildListingsGrid(listings);
      },
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return _buildEmptyState('No results found', 'Try different keywords');
    }

    return _buildListingsGrid(_searchResults);
  }

  Widget _buildTrendingTab() {
    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getListings(
        filters: MarketplaceFilters(sortBy: 'popularity'),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data ?? [];
        return _buildListingsGrid(listings);
      },
    );
  }

  Widget _buildMyListingsTab() {
    final userId = MarketplaceService.currentUserId;
    if (userId == null) {
      return _buildEmptyState('Not authenticated', 'Please log in to view your listings');
    }

    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getUserListings(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data ?? [];

        if (listings.isEmpty) {
          return _buildEmptyState(
            'No listings yet',
            'Tap the Sell button to create your first listing',
          );
        }

        return _buildListingsGrid(listings);
      },
    );
  }

  Widget _buildWatchlistTab() {
    // TODO: Implement watchlist functionality
    return _buildEmptyState('Watchlist', 'Feature coming soon!');
  }

  Widget _buildMySalesTab() {
    final userId = MarketplaceService.currentUserId;
    if (userId == null) {
      return _buildEmptyState('Not authenticated', 'Please log in to view your sales');
    }

    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getUserSoldListings(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final sales = snapshot.data ?? [];

        if (sales.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sell_outlined,
                  size: 80,
                  color: Colors.orange.withOpacity(0.5),
                ),
                SizedBox(height: 16),
                Text(
                  'No sales yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your sold items will appear here',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SellerVerificationScreen(),
                      ),
                    );
                  },
                  icon: Icon(Icons.nfc),
                  label: Text('Verify & Ship'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _buildSalesGrid(sales);
      },
    );
  }

  Widget _buildMyPurchasesTab() {
    final userId = MarketplaceService.currentUserId;
    if (userId == null) {
      return _buildEmptyState('Not authenticated', 'Please log in to view your purchases');
    }

    return StreamBuilder<List<Listing>>(
      stream: MarketplaceService.getUserPurchasedListings(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        final purchases = snapshot.data ?? [];

        if (purchases.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 80,
                  color: Colors.green.withOpacity(0.5),
                ),
                SizedBox(height: 16),
                Text(
                  'No purchases yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your purchased items will appear here',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BuyerVerificationScreen(),
                      ),
                    );
                  },
                  icon: Icon(Icons.verified_user),
                  label: Text('Track & Receive'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _buildPurchasesGrid(purchases);
      },
    );
  }

  Widget _buildSalesGrid(List<Listing> sales) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: sales.length,
      itemBuilder: (context, index) {
        final sale = sales[index];
        return _buildSaleCard(sale);
      },
    );
  }

  Widget _buildPurchasesGrid(List<Listing> purchases) {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: purchases.length,
      itemBuilder: (context, index) {
        final purchase = purchases[index];
        return _buildPurchaseCard(purchase);
      },
    );
  }

  Widget _buildSaleCard(Listing sale) {
    return GestureDetector(
      onTap: () {
        // Navigate to the new My Sales screen for detailed view
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MySalesScreen(),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Token/Item image
                if (sale.images.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      sale.images.first,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.token, color: Colors.orange),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.token, color: Colors.orange),
                  ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '\$${sale.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'SOLD',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_shipping, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap to view shipping details & manage',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(Listing purchase) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Token image placeholder
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.token, color: Colors.green),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '\$${purchase.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Status: ${purchase.status}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Widget _buildListingsGrid(List<Listing> listings) {
    return GridView.builder(
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,  // Adjusted to give more vertical space
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        final listing = listings[index];
        return _buildListingCard(listing);
      },
    );
  }

  Widget _buildListingCard(Listing listing) {
    return GestureDetector(
      onTap: () {
        // Increment views
        MarketplaceService.incrementListingViews(listing.id);
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ListingDetailScreen(listing: listing),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with rarity badge
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      color: Colors.grey[800],
                    ),
                    child: listing.images.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                            child: Image.network(
                              listing.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildPlaceholderImage();
                              },
                            ),
                          )
                        : _buildPlaceholderImage(),
                  ),
                  // Rarity badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getRarityColor(listing.metadata['tokenRarity'] ?? 'common'),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        (listing.metadata['tokenRarity'] ?? 'common').toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Details
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title and price section
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            listing.metadata['tokenName'] ?? listing.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            listing.metadata['tokenSeries'] ?? '',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '\$${listing.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom row with views and condition
                    Row(
                      children: [
                        Icon(Icons.remove_red_eye, color: Colors.grey[400], size: 14),
                        SizedBox(width: 4),
                        Text(
                          '${listing.views}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                        Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getConditionColor(listing.condition),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            listing.condition.toUpperCase(),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Icon(
        Icons.nfc,
        color: Colors.grey[600],
        size: 48,
      ),
    );
  }

  Color _getConditionColor(String condition) {
    switch (condition.toLowerCase()) {
      case 'mint':
        return Colors.green;
      case 'near_mint':
        return Colors.lightGreen;
      case 'good':
        return Colors.orange;
      case 'fair':
        return Colors.deepOrange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getRarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'rare':
        return Colors.amber;
      case 'uncommon':
        return Colors.blue;
      case 'common':
      default:
        return Colors.green;
    }
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
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

  Widget _buildFiltersBottomSheet() {
    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filters = MarketplaceFilters();
                      });
                    },
                    child: Text('Clear All'),
                  ),
                ],
              ),
              SizedBox(height: 20),

              // Price Range
              Text(
                'Price Range',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Min',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _filters = MarketplaceFilters(
                          minPrice: double.tryParse(value),
                          maxPrice: _filters.maxPrice,
                          conditions: _filters.conditions,
                          tags: _filters.tags,
                          location: _filters.location,
                          shippingAvailable: _filters.shippingAvailable,
                          listingType: _filters.listingType,
                          sortBy: _filters.sortBy,
                        );
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Max',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _filters = MarketplaceFilters(
                          minPrice: _filters.minPrice,
                          maxPrice: double.tryParse(value),
                          conditions: _filters.conditions,
                          tags: _filters.tags,
                          location: _filters.location,
                          shippingAvailable: _filters.shippingAvailable,
                          listingType: _filters.listingType,
                          sortBy: _filters.sortBy,
                        );
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),

              // Apply Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    this.setState(() {}); // Refresh the main screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Apply Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 