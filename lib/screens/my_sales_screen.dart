import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/marketplace_service.dart';
import '../models/marketplace_models.dart';

class MySalesScreen extends StatefulWidget {
  @override
  _MySalesScreenState createState() => _MySalesScreenState();
}

class _MySalesScreenState extends State<MySalesScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('My Sales'),
          backgroundColor: Colors.black,
        ),
        body: Center(
          child: Text('Please log in to view your sales'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('My Sales'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('marketplace_listings')
            .where('sellerId', isEqualTo: userId)
            .where('status', isEqualTo: 'sold')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final sales = snapshot.data!.docs;
          
          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final sale = sales[index].data() as Map<String, dynamic>;
              return _buildSaleCard(sale, sales[index].id);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sell_outlined,
            size: 80,
            color: Colors.grey[600],
          ),
          SizedBox(height: 16),
          Text(
            'No Sales Yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your sold items will appear here',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale, String saleId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore
          .collection('shipping_info')
          .doc(saleId)
          .get(),
      builder: (context, shippingSnapshot) {
        final shippingData = shippingSnapshot.data?.data() as Map<String, dynamic>?;
        
        return Card(
          color: Colors.grey[900],
          margin: EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item info
                Row(
                  children: [
                    if (sale['images'] != null && (sale['images'] as List).isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          sale['images'][0],
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale['title'] ?? 'SwapDot',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '\$${sale['price']?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'SOLD',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                Divider(color: Colors.grey[700], height: 32),
                
                // Shipping info
                Text(
                  'Ship To:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                
                if (shippingData != null) ...[
                  _buildInfoRow(Icons.person, shippingData['name'] ?? 'N/A'),
                  if (shippingData['address'] != null)
                    _buildAddressInfo(shippingData['address']),
                  if (shippingData['email'] != null)
                    _buildInfoRow(Icons.email, shippingData['email']),
                  if (shippingData['phone'] != null)
                    _buildInfoRow(Icons.phone, shippingData['phone']),
                ] else if (shippingSnapshot.connectionState == ConnectionState.waiting) ...[
                  Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ] else ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.local_shipping, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Local pickup - No shipping required',
                            style: TextStyle(color: Colors.orange, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: 16),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _markAsShipped(saleId),
                        icon: Icon(Icons.local_shipping),
                        label: Text('Mark as Shipped'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _viewTransaction(sale),
                        icon: Icon(Icons.receipt_long),
                        label: Text('Details'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey[600]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[400]),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressInfo(dynamic address) {
    String addressText = '';
    if (address is Map) {
      addressText = [
        address['line1'],
        address['line2'],
        address['city'],
        address['state'],
        address['postal_code'],
        address['country'],
      ].where((e) => e != null && e.toString().isNotEmpty).join(', ');
    } else if (address is String) {
      addressText = address;
    }
    
    return _buildInfoRow(Icons.location_on, addressText);
  }

  Future<void> _markAsShipped(String listingId) async {
    try {
      await _firestore.collection('marketplace_listings').doc(listingId).update({
        'shippedAt': FieldValue.serverTimestamp(),
        'trackingNumber': await _showTrackingNumberDialog(),
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked as shipped!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<String?> _showTrackingNumberDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Tracking Number'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Tracking Number (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  void _viewTransaction(Map<String, dynamic> sale) {
    // Navigate to transaction details or show more info
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sale Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title: ${sale['title']}'),
            Text('Price: \$${sale['price']}'),
            Text('Sold: ${sale['soldAt']?.toDate().toString() ?? 'Unknown'}'),
            if (sale['paymentIntentId'] != null)
              Text('Payment ID: ${sale['paymentIntentId']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
} 