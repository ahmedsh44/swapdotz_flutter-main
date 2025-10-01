import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'services/firebase_service.dart';

class FirebaseDemoScreen extends StatefulWidget {
  @override
  _FirebaseDemoScreenState createState() => _FirebaseDemoScreenState();
}

class _FirebaseDemoScreenState extends State<FirebaseDemoScreen> {
  User? _currentUser;
  bool _isLoading = false;
  String _statusMessage = '';
  
  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }
  
  void _checkCurrentUser() {
    setState(() {
      _currentUser = FirebaseAuth.instance.currentUser;
    });
  }
  
  Future<void> _authenticateAnonymously() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Authenticating...';
    });
    
    try {
      final user = await SwapDotzFirebaseService.authenticateAnonymously();
      setState(() {
        _currentUser = user;
        _statusMessage = 'Authenticated as: ${user?.uid}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Authentication error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _testRegisterToken() async {
    if (_currentUser == null) {
      setState(() {
        _statusMessage = 'Please authenticate first';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Registering test token...';
    });
    
    try {
      final result = await SwapDotzFirebaseService.registerToken(
        tokenUid: 'TEST_TOKEN_${DateTime.now().millisecondsSinceEpoch}',
        keyHash: 'test_key_hash_${DateTime.now().millisecondsSinceEpoch}',
        metadata: {
          'series': 'Demo',
          'edition': '001',
          'rarity': 'common',
        },
      );
      
      setState(() {
        _statusMessage = 'Token registered successfully: ${result['token_uid']}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _testInitiateTransfer() async {
    if (_currentUser == null) {
      setState(() {
        _statusMessage = 'Please authenticate first';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating transfer session...';
    });
    
    try {
      // For demo, we'll need a token UID - in real app, this would come from NFC scan
      final transfer = await SwapDotzFirebaseService.initiateTransfer(
        tokenUid: 'TEST_TOKEN_DEMO', // You'd need to register this first
      );
      
      setState(() {
        _statusMessage = '''
Transfer session created!
Session ID: ${transfer.sessionId}
Expires at: ${transfer.expiresAt}
Challenge: ${transfer.challenge ?? 'No challenge'}
''';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
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
        title: Text('Firebase Integration Demo'),
        backgroundColor: Color(0xFF00CED1),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // User Status Card
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User Status',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00CED1),
                        ),
                      ),
                      SizedBox(height: 12),
                      if (_currentUser != null) ...[
                        Text(
                          'Authenticated',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'UID: ${_currentUser!.uid}',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Not authenticated',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Authentication Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _authenticateAnonymously,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF00CED1),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _currentUser == null ? 'Authenticate Anonymously' : 'Re-authenticate',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Register Token Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _testRegisterToken,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF8C42),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Test Register Token',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Initiate Transfer Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _testInitiateTransfer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF32CD32),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Test Initiate Transfer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                SizedBox(height: 24),
                
                // Status Message Card
                if (_statusMessage.isNotEmpty)
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Loading Indicator
                if (_isLoading)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00CED1)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 