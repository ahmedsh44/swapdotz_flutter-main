import 'package:flutter/material.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';
import 'listing_detail_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({Key? key}) : super(key: key);

  @override
  _WatchlistScreenState createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<Listing> _watchlistItems = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }
  
  Future<void> _loadWatchlist() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get user's favorited listing IDs
      final favoritedIds = await MarketplaceService.getUserFavorites();
      
      // Load the actual listings
      final listings = <Listing>[];
      for (final id in favoritedIds) {
        final listing = await MarketplaceService.getListing(id);
        if (listing != null) {
          // Include all listings, even if not active, so user knows what happened
          listings.add(listing);
        }
      }
      
      // Sort by status - active listings first
      listings.sort((a, b) {
        if (a.status == ListingStatus.active && b.status != ListingStatus.active) return -1;
        if (a.status != ListingStatus.active && b.status == ListingStatus.active) return 1;
        return 0;
      });
      
      setState(() {
        _watchlistItems = listings;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading watchlist: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text('My Watchlist'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadWatchlist,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Colors.blue,
              ),
            )
          : _watchlistItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 80,
                        color: Colors.grey[600],
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Your watchlist is empty',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap the heart icon on listings to add them here',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWatchlist,
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _watchlistItems.length,
                    itemBuilder: (context, index) {
                      final listing = _watchlistItems[index];
                      return _buildWatchlistCard(listing);
                    },
                  ),
                ),
    );
  }
  
  Widget _buildWatchlistCard(Listing listing) {
    final isActive = listing.status == ListingStatus.active;
    
    return Card(
      color: isActive ? Colors.grey[900] : Colors.grey[900]?.withOpacity(0.5),
      margin: EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isActive ? () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ListingDetailScreen(listing: listing),
            ),
          );
          // Reload in case the item was unfavorited
          _loadWatchlist();
        } : null,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              // Image placeholder
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    if (listing.images.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          listing.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.image,
                              color: Colors.grey[600],
                            );
                          },
                        ),
                      )
                    else
                      Icon(
                        Icons.image,
                        color: Colors.grey[600],
                      ),
                    // Overlay for non-active listings
                    if (!isActive)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            listing.status == ListingStatus.sold ? 'SOLD' : 'REMOVED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey[500],
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: isActive ? null : TextDecoration.lineThrough,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      '\$${listing.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isActive ? Colors.blue : Colors.grey[600],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        decoration: isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        if (isActive) ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getConditionColor(listing.condition).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              listing.condition[0].toUpperCase() + listing.condition.substring(1),
                              style: TextStyle(
                                color: _getConditionColor(listing.condition),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (listing.shippingAvailable) ...[
                            SizedBox(width: 8),
                            Icon(
                              Icons.local_shipping,
                              size: 16,
                              color: Colors.green,
                            ),
                          ],
                        ] else ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: listing.status == ListingStatus.sold 
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              listing.status == ListingStatus.sold ? 'Sold' : 'No longer available',
                              style: TextStyle(
                                color: listing.status == ListingStatus.sold 
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Remove from watchlist button
              IconButton(
                icon: Icon(
                  Icons.favorite,
                  color: Colors.red,
                ),
                onPressed: () async {
                  await MarketplaceService.toggleFavorite(listing.id, false);
                  _loadWatchlist();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed from watchlist'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Color _getConditionColor(String condition) {
    switch (condition.toLowerCase()) {
      case 'mint':
        return Colors.green;
      case 'near mint':
        return Colors.lightGreen;
      case 'good':
        return Colors.blue;
      case 'fair':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
} 