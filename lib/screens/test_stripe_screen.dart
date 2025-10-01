import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/payment_service.dart';
import '../models/marketplace_models.dart';

class TestStripeScreen extends StatefulWidget {
  const TestStripeScreen({Key? key}) : super(key: key);

  @override
  _TestStripeScreenState createState() => _TestStripeScreenState();
}

class _TestStripeScreenState extends State<TestStripeScreen> {
  bool _isLoading = false;
  String _status = 'Select a listing to test payment';
  User? _currentUser;
  Listing? _selectedListing;
  List<Listing> _availableListings = [];

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _loadListings();
  }

  Future<void> _checkAuth() async {
    setState(() {
      _currentUser = FirebaseAuth.instance.currentUser;
      if (_currentUser != null) {
        _status = 'Authenticated as: ${_currentUser!.email ?? _currentUser!.uid.substring(0, 8)}...';
      } else {
        _status = 'Not authenticated. Will sign in when testing.';
      }
    });
  }

  Future<void> _loadListings() async {
    try {
      // Get first 10 active listings from marketplace
      final snapshot = await FirebaseFirestore.instance
          .collection('marketplace_listings')
          .where('status', isEqualTo: 'active')
          .limit(10)
          .get();
      
      final listings = snapshot.docs.map((doc) {
        return Listing.fromFirestore(doc);
      }).toList();
      
      setState(() {
        _availableListings = listings;
        if (listings.isNotEmpty) {
          _status = 'Select a listing below to test payment';
        } else {
          _status = 'No active listings found. Create one in the marketplace first.';
        }
      });
    } catch (e) {
      setState(() {
        _status = 'Error loading listings: $e';
      });
    }
  }

  Future<void> _ensureAuthenticated() async {
    if (FirebaseAuth.instance.currentUser == null) {
      setState(() {
        _status = 'Signing in anonymously...';
      });
      
      try {
        // Sign in anonymously for testing
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        _currentUser = userCredential.user;
        setState(() {
          _status = 'Signed in as anonymous user';
        });
      } catch (e) {
        throw Exception('Failed to authenticate: $e');
      }
    }
  }

  Future<void> _testPayment() async {
    if (_selectedListing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a listing first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Initializing payment...';
    });

    try {
      // Ensure user is authenticated first
      await _ensureAuthenticated();
      
      // Test payment for selected listing
      await PaymentService.initPaymentSheet(
        listingId: _selectedListing!.id,
        amount: _selectedListing!.price,
        sellerName: _selectedListing!.sellerDisplayName,
      );

      setState(() {
        _status = 'Payment sheet initialized. Presenting...';
      });

      // Present the payment sheet
      await PaymentService.presentPaymentSheet();

      setState(() {
        _status = '✅ Payment successful!';
      });
    } on StripeException catch (e) {
      setState(() {
        _status = '❌ Payment cancelled or failed: ${e.error.localizedMessage}';
      });
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Stripe Integration'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.payment,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'Stripe Test Payment',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Test card: 4242 4242 4242 4242',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _status.contains('✅')
                        ? Colors.green
                        : _status.contains('❌')
                            ? Colors.red
                            : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Listings selector
              if (_availableListings.isNotEmpty) ...[
                const Text(
                  'Available Listings:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableListings.length,
                    itemBuilder: (context, index) {
                      final listing = _availableListings[index];
                      final isSelected = _selectedListing?.id == listing.id;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedListing = listing;
                            _status = 'Selected: ${listing.title} - \$${listing.price.toStringAsFixed(2)}';
                          });
                        },
                        child: Container(
                          width: 100,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.nfc,
                                size: 30,
                                color: isSelected ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                listing.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '\$${listing.price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.blue : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
              ElevatedButton(
                onPressed: _isLoading || _selectedListing == null ? null : _testPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _selectedListing != null 
                          ? 'Pay \$${_selectedListing!.price.toStringAsFixed(2)}'
                          : 'Select a Listing First',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 40),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(15.0),
                  child: Column(
                    children: [
                      Text(
                        '🔒 Test Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'This is using Stripe test keys.\nNo real money will be charged.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 