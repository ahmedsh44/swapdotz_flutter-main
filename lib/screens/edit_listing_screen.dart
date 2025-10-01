import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/marketplace_models.dart';
import '../services/marketplace_service.dart';

class EditListingScreen extends StatefulWidget {
  final Listing listing;

  const EditListingScreen({Key? key, required this.listing}) : super(key: key);

  @override
  _EditListingScreenState createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _locationController;
  late TextEditingController _shippingCostController;
  
  late String _selectedCondition;
  late ListingType _selectedType;
  late bool _shippingAvailable;
  late List<String> _selectedTags;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with existing values
    _titleController = TextEditingController(text: widget.listing.title);
    _descriptionController = TextEditingController(text: widget.listing.description);
    _priceController = TextEditingController(text: widget.listing.price.toString());
    _locationController = TextEditingController(text: widget.listing.location ?? '');
    _shippingCostController = TextEditingController(
      text: widget.listing.shippingCost?.toString() ?? ''
    );
    
    // Fix condition casing - handle underscores and capitalize properly
    final condition = widget.listing.condition;
    if (condition == 'near_mint') {
      _selectedCondition = 'Near Mint';
    } else if (condition.isNotEmpty) {
      _selectedCondition = condition[0].toUpperCase() + condition.substring(1).toLowerCase();
    } else {
      _selectedCondition = 'Good'; // Default if empty
    }
    
    _selectedType = widget.listing.type;
    _shippingAvailable = widget.listing.shippingAvailable;
    _selectedTags = List<String>.from(widget.listing.tags);
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

  Future<void> _updateListing() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('DEBUG: Updating listing ${widget.listing.id}');
      print('DEBUG: Title: ${_titleController.text.trim()}');
      print('DEBUG: Price: ${_priceController.text}');
      print('DEBUG: Type: $_selectedType');
      
      await MarketplaceService.updateListing(
        listingId: widget.listing.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text),
        condition: _selectedCondition == 'Near Mint' ? 'near_mint' : _selectedCondition.toLowerCase(), // Handle Near Mint special case
        tags: _selectedTags,
        type: _selectedType,
        location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        shippingAvailable: _shippingAvailable,
        shippingCost: _shippingAvailable && _shippingCostController.text.isNotEmpty
            ? double.tryParse(_shippingCostController.text)
            : null,
      );

      print('DEBUG: Listing updated successfully');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Listing updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to indicate update
    } catch (e, stackTrace) {
      print('ERROR: Failed to update listing: $e');
      print('STACK TRACE: $stackTrace');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update listing: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
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
        title: Text('Edit Listing'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _updateListing,
            child: Text(
              'Save',
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
            // Token Info (Read-only)
            _buildSectionTitle('Token'),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Token ID: ${widget.listing.tokenId}',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'This cannot be changed',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
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
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
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
              ],
            ),
            SizedBox(height: 24),

            // Condition & Type
            _buildSectionTitle('Details'),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown<String>(
                    label: 'Condition',
                    value: _selectedCondition,
                    items: ['Mint', 'Near Mint', 'Good', 'Fair', 'Poor']
                        .map((condition) => DropdownMenuItem(
                              value: condition,
                              child: Text(condition, style: TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCondition = value!;
                      });
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
                                type.toString().split('.').last,
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

            // Tags
            _buildSectionTitle('Tags'),
            _buildTagsSection(),
            SizedBox(height: 24),

            // Shipping
            _buildSectionTitle('Shipping'),
            _buildShippingSection(),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.white),
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintStyle: TextStyle(color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[700]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[700]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[700]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              dropdownColor: Colors.grey[900],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection() {
    final availableTags = [
      'Sports', 'Music', 'Gaming', 'Art', 'Movies', 'TV Shows',
      'Anime', 'Comics', 'Books', 'Technology', 'Fashion', 'Collectibles',
      'Vintage', 'Limited Edition', 'Rare', 'Exclusive'
    ];

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
          children: availableTags.map((tag) {
            final isSelected = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
              selectedColor: Colors.blue.withOpacity(0.3),
              backgroundColor: Colors.grey[800],
              labelStyle: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[300],
              ),
              checkmarkColor: Colors.blue,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildShippingSection() {
    return Column(
      children: [
        SwitchListTile(
          title: Text('Available for Shipping', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            'Allow buyers from other locations to purchase',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
          value: _shippingAvailable,
          onChanged: (value) {
            setState(() {
              _shippingAvailable = value;
              if (!value) {
                _shippingCostController.clear();
              }
            });
          },
          activeColor: Colors.blue,
        ),
        if (_shippingAvailable) ...[
          SizedBox(height: 16),
          _buildTextField(
            controller: _shippingCostController,
            label: 'Shipping Cost (\$)',
            hint: 'Leave empty for free shipping',
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
          ),
        ],
        SizedBox(height: 16),
        _buildTextField(
          controller: _locationController,
          label: 'Location (Optional)',
          hint: 'e.g., New York, NY',
        ),
      ],
    );
  }
} 