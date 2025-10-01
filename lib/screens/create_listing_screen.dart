import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';
import '../services/firebase_service.dart';
import '../services/image_service.dart';

class CreateListingScreen extends StatefulWidget {
  @override
  _CreateListingScreenState createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _shippingCostController = TextEditingController();
  
  String _selectedTokenId = '';
  String _selectedCondition = 'good';
  ListingType _selectedType = ListingType.fixed_price;
  bool _shippingAvailable = false;
  List<String> _selectedTags = [];
  List<Token> _userTokens = [];
  bool _isLoading = false;
  bool _loadingTokens = true;
  
  // Token metadata fields (read-only)
  String _tokenName = '';
  String _tokenSeries = '';
  String _tokenRarity = '';
  
  // Image handling
  List<File> _selectedImages = [];
  bool _uploadingImages = false;

  final List<String> _conditions = ['mint', 'near_mint', 'good', 'fair', 'poor'];
  final List<String> _availableTags = [
    'rare', 'vintage', 'limited', 'collectible', 'celebrity', 'sports',
    'gaming', 'tech', 'art', 'music', 'movie', 'tv', 'anime', 'comics'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserTokens();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _shippingCostController.dispose();
    super.dispose();
  }

  Future<void> _loadUserTokens() async {
    try {
      setState(() {
        _loadingTokens = true;
      });

      // Get current user ID
      final userId = await SwapDotzFirebaseService.getCurrentUserId();
      print('🛍️ CREATE LISTING: Loading tokens for userId: $userId');
      
      if (userId == null) {
        print('🛍️ CREATE LISTING: No authenticated user found');
        setState(() {
          _userTokens = [];
          _loadingTokens = false;
        });
        return;
      }

      // Get tokens owned by the current user
      final tokensStream = SwapDotzFirebaseService.getUserTokens(userId);
      
      // Get active listings to filter out already listed tokens
      final activeListingsStream = MarketplaceService.getListings();
      
      // Combine both streams to filter tokens
      tokensStream.listen((tokens) async {
        print('🛍️ CREATE LISTING: Received ${tokens.length} tokens from stream');
        
        // Get current active listings
        final activeListings = await activeListingsStream.first;
        print('🛍️ CREATE LISTING: Found ${activeListings.length} active listings');
        
        final listedTokenIds = activeListings.map((listing) => listing.tokenId).toSet();
        print('🛍️ CREATE LISTING: Listed token IDs: $listedTokenIds');
        
        // Filter out tokens that are already listed
        final availableTokens = tokens.where((token) => !listedTokenIds.contains(token.uid)).toList();
        print('🛍️ CREATE LISTING: ${availableTokens.length} tokens available after filtering');
        
        for (final token in availableTokens) {
          print('🛍️ CREATE LISTING: Available token - ID: ${token.uid}, Name: ${token.metadata.name}, Owner: ${token.currentOwnerId}');
        }
        
        setState(() {
          _userTokens = availableTokens;
          _loadingTokens = false;
          
          // Select the first token if available and none is currently selected
          if (availableTokens.isNotEmpty && _selectedTokenId.isEmpty) {
            _selectedTokenId = availableTokens.first.uid;
            // Populate metadata for the auto-selected token
            _tokenName = availableTokens.first.metadata.name ?? 'Unknown';
            _tokenSeries = availableTokens.first.metadata.series ?? 'Unknown';
            _tokenRarity = availableTokens.first.metadata.rarity ?? 'common';
            print('🛍️ CREATE LISTING: Auto-selected first token: $_selectedTokenId');
          } else if (availableTokens.isEmpty) {
            _selectedTokenId = '';
            _tokenName = '';
            _tokenSeries = '';
            _tokenRarity = '';
            print('🛍️ CREATE LISTING: No tokens available to select');
          }
        });
      });
    } catch (e) {
      print('🛍️ CREATE LISTING ERROR: $e');
      setState(() {
        _userTokens = [];
        _loadingTokens = false;
      });
    }
  }

  Future<void> _removeStaleListings() async {
    try {
      print('🧹 Removing stale listings for current user tokens...');
      
      // Get all active listings
      final listings = await MarketplaceService.getListings().first;
      
      // Find listings for tokens the user owns
      final userId = await SwapDotzFirebaseService.getCurrentUserId();
      if (userId == null) return;
      
      final userTokens = await SwapDotzFirebaseService.getUserTokens(userId).first;
      final userTokenIds = userTokens.map((t) => t.uid).toSet();
      
      int removed = 0;
      for (final listing in listings) {
        if (userTokenIds.contains(listing.tokenId)) {
          // Check if this is the user's listing
          if (listing.sellerId != userId) {
            print('🧹 Found stale listing: ${listing.id} for token ${listing.tokenId} by seller ${listing.sellerId}');
            print('🧹 This listing is blocking token from being listed by current owner');
            // Can't remove other user's listings, but we can report it
            removed++;
          } else {
            print('🧹 Found your own listing: ${listing.id} for token ${listing.tokenId}');
            // Could offer to remove it
            await MarketplaceService.removeListing(listing.id);
            print('🧹 Removed your listing: ${listing.id}');
            removed++;
          }
        }
      }
      
      if (removed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found $removed listings. Reloading tokens...'),
            backgroundColor: Colors.orange,
          ),
        );
        // Reload tokens
        _loadUserTokens();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No stale listings found'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('🧹 Error removing stale listings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _selectImage(ImageSource source) async {
    if (_selectedImages.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum 5 images allowed')),
      );
      return;
    }
    
    final processedImage = await ImageService.pickAndProcessImage(
      context: context,
      source: source,
      allowCropping: true,
    );
    
    if (processedImage != null) {
      setState(() {
        _selectedImages.add(processedImage);
      });
    }
  }
  
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }
  
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library, color: Colors.blue),
              title: Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _selectImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: Colors.blue),
              title: Text('Take a Photo', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _selectImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.cancel, color: Colors.grey),
              title: Text('Cancel', style: TextStyle(color: Colors.grey)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createListing() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTokenId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a token to list')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadingImages = true;
    });

    try {
      // Upload images first
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        final userId = MarketplaceService.currentUserId ?? 'unknown';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final basePath = 'listings/$userId/$timestamp';
        
        imageUrls = await ImageService.uploadMultipleImages(
          imageFiles: _selectedImages,
          basePath: basePath,
          onProgress: (current, total) {
            print('Uploading image ${current + 1} of $total');
          },
        );
      }
      
      setState(() {
        _uploadingImages = false;
      });
      
      await MarketplaceService.createListing(
        tokenId: _selectedTokenId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text),
        images: imageUrls,
        condition: _selectedCondition.toLowerCase(), // Save as lowercase for consistency
        tags: _selectedTags,
        type: _selectedType,
        location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        shippingAvailable: _shippingAvailable,
        shippingCost: _shippingAvailable && _shippingCostController.text.isNotEmpty
            ? double.tryParse(_shippingCostController.text)
            : null,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Listing created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create listing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
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
        title: Text('Create Listing'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createListing,
            child: Text(
              'Create',
              style: TextStyle(
                color: _isLoading ? Colors.grey : Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Token Selection
            _buildSectionTitle('Select Token'),
            _buildTokenDropdown(),
            
            // Token Details (Read-only)
            if (_selectedTokenId.isNotEmpty) ...[
              SizedBox(height: 16),
              _buildTokenMetadataSection(),
            ],
            SizedBox(height: 24),

            // Photos
            _buildSectionTitle('Photos'),
            Text(
              'Add up to 5 photos of your SwapDot',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            SizedBox(height: 12),
            _buildImageSection(),
            SizedBox(height: 24),

            // Basic Information
            _buildSectionTitle('Basic Information'),
            _buildTextField(
              controller: _titleController,
              label: 'Title',
              hint: 'e.g., Michael Jordan Rookie SwapDot',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            _buildTextField(
              controller: _descriptionController,
              label: 'Description',
              hint: 'Describe your SwapDot in detail...',
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            SizedBox(height: 24),

            // Pricing
            _buildSectionTitle('Pricing'),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _priceController,
                    label: 'Price (\$)',
                    hint: '0.00',
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a price';
                      }
                      final price = double.tryParse(value);
                      if (price == null || price <= 0) {
                        return 'Please enter a valid price';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _buildDropdown<ListingType>(
                    label: 'Type',
                    value: _selectedType,
                    items: ListingType.values
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type.toString().split('.').last.replaceAll('_', ' '),
                                style: TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Condition
            _buildSectionTitle('Condition'),
            _buildDropdown<String>(
              label: 'Condition',
              value: _selectedCondition,
              items: _conditions
                  .map((condition) => DropdownMenuItem(
                        value: condition,
                        child: Text(
                          condition.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(color: Colors.white),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCondition = value!;
                });
              },
            ),
            SizedBox(height: 24),

            // Tags
            _buildSectionTitle('Tags'),
            _buildTagsSection(),
            SizedBox(height: 24),

            // Shipping
            _buildSectionTitle('Shipping'),
            _buildShippingSection(),
            SizedBox(height: 24),

            // Location (optional)
            _buildSectionTitle('Location (Optional)'),
            _buildTextField(
              controller: _locationController,
              label: 'Location',
              hint: 'e.g., New York, NY',
            ),
            SizedBox(height: 32),

            // Create Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createListing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        'Create Listing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintStyle: TextStyle(color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        dropdownColor: Colors.grey[800],
        style: TextStyle(color: Colors.white),
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        isDense: false,
        menuMaxHeight: 400,
        itemHeight: null, // Allow dynamic height for items
      ),
    );
  }

  Widget _buildTokenDropdown() {
    if (_loadingTokens) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading your SwapDotz...',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    if (_userTokens.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No SwapDotz available to list',
              style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Your tokens might already be listed. Try removing stale listings.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _removeStaleListings,
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Check for Stale Listings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return _buildDropdown<String>(
      label: 'Token',
      value: _selectedTokenId,
      items: _userTokens
          .map((token) => DropdownMenuItem(
                value: token.uid,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        token.metadata.name ?? 'Unknown Token',
                        style: TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Series: ${token.metadata.series ?? 'Unknown'} • ID: ${token.uid.substring(0, 8)}...',
                        style: TextStyle(
                          color: Colors.grey[400], 
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedTokenId = value!;
          // Find the selected token and populate metadata
          final selectedToken = _userTokens.firstWhere((t) => t.uid == value);
          _tokenName = selectedToken.metadata.name ?? 'Unknown';
          _tokenSeries = selectedToken.metadata.series ?? 'Unknown';
          _tokenRarity = selectedToken.metadata.rarity ?? 'common';
        });
      },
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select tags that describe your SwapDot:',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableTags.map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(
                tag,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[400],
                ),
              ),
              selected: isSelected,
              backgroundColor: Colors.grey[800],
              selectedColor: Colors.blue,
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
            );
          }).toList(),
        ),
        if (_selectedTags.isNotEmpty) ...[
          SizedBox(height: 12),
          Text(
            'Selected: ${_selectedTags.join(', ')}',
            style: TextStyle(color: Colors.blue, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildShippingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(
            'Offer Shipping',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            'Allow buyers to purchase with shipping',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
          value: _shippingAvailable,
          activeColor: Colors.blue,
          onChanged: (value) {
            setState(() {
              _shippingAvailable = value;
            });
          },
        ),
        if (_shippingAvailable) ...[
          SizedBox(height: 16),
          _buildTextField(
            controller: _shippingCostController,
            label: 'Shipping Cost (\$)',
            hint: '0.00',
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ],
    );
  }

  Widget _buildTokenMetadataSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text(
                'Token Information',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _buildMetadataRow('Name', _tokenName),
          SizedBox(height: 8),
          _buildMetadataRow('Series', _tokenSeries),
          SizedBox(height: 8),
          _buildMetadataRow('Rarity', _getRarityDisplay(_tokenRarity)),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: _tokenRarity.toLowerCase() == 'rare' ? Colors.amber :
                     _tokenRarity.toLowerCase() == 'uncommon' ? Colors.blue :
                     Colors.green,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String _getRarityDisplay(String rarity) {
    final rarityLower = rarity.toLowerCase();
    switch (rarityLower) {
      case 'rare':
        return '⭐⭐⭐ RARE';
      case 'uncommon':
        return '⭐⭐ UNCOMMON';
      case 'common':
      default:
        return '⭐ COMMON';
    }
  }

  Widget _buildImageSection() {
    return Column(
      children: [
        if (_selectedImages.isNotEmpty) ...[
          SizedBox(height: 12),
          Text(
            'Selected Images (${_selectedImages.length}/5)',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_selectedImages.length, (index) {
              return Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: FileImage(_selectedImages[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: () => _removeImage(index),
                      icon: Icon(Icons.close, color: Colors.red, size: 20),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
        if (_selectedImages.length < 5) ...[
          SizedBox(height: 12),
          Text(
            'Tap the + button to add more photos',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          SizedBox(height: 12),
          ElevatedButton(
            onPressed: _showImageSourceDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Add Photo',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ],
    );
  }
} 