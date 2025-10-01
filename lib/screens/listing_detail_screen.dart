import 'package:flutter/material.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';
import '../services/payment_service.dart'; // Added import for PaymentService
import '../config/stripe_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'edit_listing_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  final Listing listing;

  const ListingDetailScreen({Key? key, required this.listing}) : super(key: key);

  @override
  _ListingDetailScreenState createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final PageController _imageController = PageController();
  final TextEditingController _offerController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isLoading = false;
  bool _isFavorite = false;

  @override
  void dispose() {
    _imageController.dispose();
    _offerController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _refreshListing() async {
    // Trigger a rebuild to show updated listing status
    // In a real app, you might want to refetch the listing from Firestore
    if (mounted) {
      setState(() {
        // This will trigger a rebuild of the UI
      });
    }
  }

  Future<void> _makeOffer() async {
    final amount = double.tryParse(_offerController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid offer amount')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await MarketplaceService.makeOffer(
        listingId: widget.listing.id,
        amount: amount,
        message: _messageController.text.isEmpty ? null : _messageController.text,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer submitted successfully!')),
      );

      Navigator.pop(context); // Close the offer dialog
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit offer: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _buyNow() async {
    // Calculate total amount including shipping if applicable
    final double totalAmount = widget.listing.shippingAvailable && widget.listing.shippingCost != null
        ? widget.listing.price + widget.listing.shippingCost!
        : widget.listing.price;
    
    // If shipping is required, use Checkout Session for address collection
    if (widget.listing.shippingAvailable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Purchase with Shipping',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase "${widget.listing.title}"',
                style: TextStyle(color: Colors.grey[300], fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Item Price: \$${widget.listing.price.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey[300]),
              ),
              if (widget.listing.shippingCost != null && widget.listing.shippingCost! > 0)
                Text(
                  'Shipping: \$${widget.listing.shippingCost!.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey[300]),
                ),
              Divider(color: Colors.grey[700]),
              Text(
                'Total: \$${totalAmount.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                '📍 You will enter your shipping address on the next page',
                style: TextStyle(color: Colors.blue[300], fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text('Continue to Checkout'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        _isLoading = true;
      });

      try {
        // Launch Stripe Checkout Session with shipping collection
        await PaymentService.launchCheckoutSession(
          listingId: widget.listing.id,
          amount: totalAmount,
          requiresShipping: true,
        );
        
        // Note: User will complete payment in browser
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening checkout in browser...'),
            backgroundColor: Colors.blue,
          ),
        );
      } catch (e) {
        print('Payment error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
    else {
      // For non-shipping items, use the regular payment sheet
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Confirm Purchase', style: TextStyle(color: Colors.white)),
          content: Text(
            'Are you sure you want to buy "${widget.listing.title}" for \$${widget.listing.price.toStringAsFixed(2)}?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text('Buy Now'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() {
        _isLoading = true;
      });

      try {
        // Use regular payment sheet for local pickup items
        await PaymentService.initPaymentSheet(
          listingId: widget.listing.id,
          amount: totalAmount,
          sellerName: widget.listing.sellerDisplayName,
          requiresShipping: false,
          shippingCost: 0,
        );

                // Present payment sheet to user
        await PaymentService.presentPaymentSheet();
        
        // If we reach here, payment was successful
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('✅ Payment successful! Transaction initiated.')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
        
        // Refresh the listing to show updated status
        _refreshListing();
        
      } catch (e) {
      // Handle payment errors and cancellations
      print('Payment error: $e');
      
      String errorMessage = 'Payment failed';
      Color backgroundColor = Colors.red;
      
      // Check if it's a user cancellation
      if (e.toString().contains('canceled') || 
          e.toString().contains('cancelled') ||
          e.toString().contains('UserCancel')) {
        errorMessage = 'Payment canceled';
        backgroundColor = Colors.orange;
      }
      // Check if it's a Stripe setup issue
      else if (e.toString().contains('payment processing not yet implemented') ||
               e.toString().contains('Stripe') ||
               e.toString().contains('payment intent') ||
               e.toString().contains('secret_key') ||
               e.toString().contains('publishable_key')) {
        
        // Show user-friendly message for payment setup issues
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💳 Payment system setup required'),
                SizedBox(height: 4),
                Text('Creating offer for full price as alternative...', 
                     style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        
        // Fallback: Create an offer for the full asking price
        try {
          await MarketplaceService.makeOffer(
            listingId: widget.listing.id,
            amount: widget.listing.price,
            message: 'Buy Now - Full Asking Price (Payment integration pending)',
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Offer created! Seller will be notified.')),
          );
        } catch (offerError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create offer: $offerError')),
          );
        }
        return; // Exit early to avoid showing the generic error message
      }
      
      // Show the error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: backgroundColor,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  } // End of else block
  } // End of _buyNow method

  void _showOfferDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Make an Offer', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Asking Price: \$${widget.listing.price.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey[400]),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _offerController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Your Offer (\$)',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _messageController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Message (optional)',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : _makeOffer,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Submit Offer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.listing.sellerId == MarketplaceService.currentUserId;
    
    // Debug logging
    print('DEBUG: Listing seller ID: ${widget.listing.sellerId}');
    print('DEBUG: Current user ID: ${MarketplaceService.currentUserId}');
    print('DEBUG: Is owner: $isOwner');

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: const Color(0xFF1E1E1E),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildImageGallery(),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.red : Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    _isFavorite = !_isFavorite;
                  });
                  MarketplaceService.toggleFavorite(widget.listing.id, _isFavorite);
                },
              ),
              if (isOwner)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditListingScreen(listing: widget.listing),
                        ),
                      );
                      // If the listing was updated, refresh the screen
                      if (result == true) {
                        // Fetch updated listing
                        final updatedListing = await MarketplaceService.getListing(widget.listing.id);
                        if (updatedListing != null && mounted) {
                          // Navigate to the updated listing detail screen
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ListingDetailScreen(listing: updatedListing),
                            ),
                          );
                        }
                      }
                    } else if (value == 'remove') {
                      _showRemoveDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Listing'),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove Listing'),
                    ),
                  ],
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Token Metadata Badge
                  if (widget.listing.metadata['tokenName'] != null || 
                      widget.listing.metadata['tokenRarity'] != null) ...[
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getRarityColor(widget.listing.metadata['tokenRarity'] ?? 'common').withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getRarityColor(widget.listing.metadata['tokenRarity'] ?? 'common'),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.nfc,
                            color: _getRarityColor(widget.listing.metadata['tokenRarity'] ?? 'common'),
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.listing.metadata['tokenName'] ?? 'SwapDot Token',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Series: ${widget.listing.metadata['tokenSeries'] ?? 'Unknown'}',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getRarityColor(widget.listing.metadata['tokenRarity'] ?? 'common'),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              (widget.listing.metadata['tokenRarity'] ?? 'common').toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                  ],

                  // Title and Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.listing.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '\$${widget.listing.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Shipping info
                            if (widget.listing.shippingAvailable) ...[
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.local_shipping, color: Colors.green, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    widget.listing.shippingCost != null && widget.listing.shippingCost! > 0
                                        ? '+ \$${widget.listing.shippingCost!.toStringAsFixed(2)} shipping'
                                        : 'Free shipping',
                                    style: TextStyle(
                                      color: widget.listing.shippingCost == null || widget.listing.shippingCost == 0
                                          ? Colors.green
                                          : Colors.grey[400],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, color: Colors.orange, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    'Local pickup only',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (widget.listing.location != null) ...[
                                    Text(
                                      ' • ${widget.listing.location}',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      _buildConditionBadge(widget.listing.condition),
                    ],
                  ),

                  SizedBox(height: 16),

                  // Seller Info
                  _buildSellerInfo(),

                  SizedBox(height: 16),

                  // Description
                  Text(
                    'Description',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.listing.description,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),

                  SizedBox(height: 16),

                  // Tags
                  if (widget.listing.tags.isNotEmpty) _buildTags(),

                  SizedBox(height: 16),

                  // Details
                  _buildDetails(),

                  SizedBox(height: 16),

                  // Offers Section (only for owner)
                  if (isOwner) _buildOffersSection(),

                  SizedBox(height: 100), // Space for bottom buttons
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isOwner ? null : _buildBottomButtons(),
    );
  }

  Widget _buildImageGallery() {
    if (widget.listing.images.isEmpty) {
      return Container(
        color: Colors.grey[800],
        child: Center(
          child: Icon(
            Icons.nfc,
            size: 80,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _imageController,
      itemCount: widget.listing.images.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            Image.network(
              widget.listing.images[index],
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[800],
                  child: Center(
                    child: Icon(
                      Icons.error,
                      size: 80,
                      color: Colors.grey[600],
                    ),
                  ),
                );
              },
            ),
            if (widget.listing.images.length > 1)
              Positioned(
                bottom: 16,
                right: 16,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${index + 1}/${widget.listing.images.length}',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildConditionBadge(String condition) {
    Color color;
    switch (condition.toLowerCase()) {
      case 'mint':
        color = Colors.green;
        break;
      case 'near_mint':
        color = Colors.lightGreen;
        break;
      case 'good':
        color = Colors.orange;
        break;
      case 'fair':
        color = Colors.deepOrange;
        break;
      case 'poor':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        condition.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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

  Widget _buildSellerInfo() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue,
            child: Text(
              widget.listing.sellerDisplayName[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.listing.sellerDisplayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Seller',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.star,
            color: Colors.amber,
            size: 16,
          ),
          Text(
            '4.8',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.listing.tags.map((tag) {
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '#$tag',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          _buildDetailRow('Token ID', widget.listing.tokenId),
          _buildDetailRow('Type', widget.listing.type.toString().split('.').last),
          _buildDetailRow('Views', '${widget.listing.views}'),
          _buildDetailRow('Favorites', '${widget.listing.favorites}'),
          if (widget.listing.location != null)
            _buildDetailRow('Location', widget.listing.location!),
          _buildDetailRow(
            'Shipping',
            widget.listing.shippingAvailable ? 'Available' : 'Not Available',
          ),
          if (widget.listing.shippingCost != null)
            _buildDetailRow('Shipping Cost', '\$${widget.listing.shippingCost!.toStringAsFixed(2)}'),
          _buildDetailRow(
            'Listed',
            '${DateTime.now().difference(widget.listing.createdAt).inDays} days ago',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Offers',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        StreamBuilder<List<Offer>>(
          stream: MarketplaceService.getListingOffers(widget.listing.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }

            final offers = snapshot.data ?? [];

            if (offers.isEmpty) {
              return Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'No offers yet',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: offers.length,
              itemBuilder: (context, index) {
                final offer = offers[index];
                return _buildOfferCard(offer);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildOfferCard(Offer offer) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
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
                  offer.buyerDisplayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '\$${offer.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (offer.message != null) ...[
            SizedBox(height: 8),
            Text(
              offer.message!,
              style: TextStyle(color: Colors.grey[300]),
            ),
          ],
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${DateTime.now().difference(offer.createdAt).inHours}h ago',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
              if (offer.status == OfferStatus.pending) ...[
                TextButton(
                  onPressed: () {
                    MarketplaceService.rejectOffer(offer.id);
                  },
                  child: Text('Reject'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    MarketplaceService.acceptOffer(offer.id);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: Text('Accept'),
                ),
              ] else ...[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getOfferStatusColor(offer.status),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    offer.status.toString().split('.').last.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _getOfferStatusColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.accepted:
        return Colors.green;
      case OfferStatus.rejected:
        return Colors.red;
      case OfferStatus.expired:
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _showOfferDialog,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.blue),
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Make Offer',
                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _buyNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Buy Now',
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
  }

  void _showRemoveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Remove Listing', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove this listing? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await MarketplaceService.removeListing(widget.listing.id);
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close detail screen
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Listing removed successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to remove listing: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Remove'),
          ),
        ],
      ),
    );
  }
} 