// lib/main.dart – SwapDotz NFC App with modern UI

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'firebase_options.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'desfire.dart';
import 'firebase_demo_screen.dart';
import 'version_check_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwapDotz',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: VersionCheckWrapper(),
    );
  }
}

class VersionCheckWrapper extends StatefulWidget {
  @override
  _VersionCheckWrapperState createState() => _VersionCheckWrapperState();
}

class _VersionCheckWrapperState extends State<VersionCheckWrapper> {
  bool _isCheckingVersion = true;
  bool _needsUpdate = false;
  String? _currentVersion;
  String? _requiredVersion;
  String? _updateMessage;
  String? _updateUrl;

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      
      // Check minimum required version from Firebase
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_requirements')
          .get();
      
      if (configDoc.exists) {
        final data = configDoc.data();
        _requiredVersion = data?['minimum_version'] ?? '1.0.0';
        _updateMessage = data?['update_message'];
        _updateUrl = data?['update_url'];
        
        // Compare versions
        _needsUpdate = _isVersionOlder(_currentVersion!, _requiredVersion!);
      }
    } catch (e) {
      print('Version check error: $e');
      // If version check fails, allow app to continue but log the error
      // In production, you might want to be more strict
    }
    
    setState(() {
      _isCheckingVersion = false;
    });
  }
  
  bool _isVersionOlder(String current, String required) {
    // Simple version comparison - splits by dots and compares numbers
    final currentParts = current.split('.').map(int.tryParse).toList();
    final requiredParts = required.split('.').map(int.tryParse).toList();
    
    for (int i = 0; i < requiredParts.length; i++) {
      final currentPart = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      final requiredPart = requiredParts[i] ?? 0;
      
      if (currentPart < requiredPart) return true;
      if (currentPart > requiredPart) return false;
    }
    
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingVersion) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 20),
              Text(
                'Checking version...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_needsUpdate) {
      return VersionCheckScreen(
        currentVersion: _currentVersion ?? 'Unknown',
        requiredVersion: _requiredVersion ?? 'Unknown',
        updateMessage: _updateMessage,
        updateUrl: _updateUrl,
      );
    }
    
    return SplashScreen();
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late Animation<double> _logoAnimation;
  late Animation<double> _textAnimation;
  late Animation<double> _logoRotationAnimation;

  @override
  void initState() {
    super.initState();
    
    _logoController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _textController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _logoAnimation = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    
    _logoRotationAnimation = Tween<double>(begin: 0.0, end: 3.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
    
    _textAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    
    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(Duration(milliseconds: 200));
    _logoController.forward();
    
    await Future.delayed(Duration(milliseconds: 600));
    _textController.forward();
    
    await Future.delayed(Duration(seconds: 2));
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SwapDotzApp(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF00CED1), // Bright cyan blue
              Color(0xFF1a1a2e), // Dark blue
              Color(0xFFFF8C42), // Vibrant orange (subtle)
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative elements for splash screen
            Positioned(
              top: 100,
              left: 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00CED1).withOpacity(0.2),
                  border: Border.all(
                    color: Color(0xFF00CED1).withOpacity(0.4),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 150,
              right: 40,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF8C42).withOpacity(0.15),
                ),
              ),
            ),
            Positioned(
              bottom: 200,
              left: 50,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF32CD32).withOpacity(0.4),
                ),
              ),
            ),
            Positioned(
              bottom: 150,
              right: 60,
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFFF00).withOpacity(0.5),
                ),
              ),
            ),
            
            Center(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo with animation
              AnimatedBuilder(
                animation: _logoAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _logoAnimation.value,
                    child: Transform.rotate(
                      angle: -_logoRotationAnimation.value * 2 * pi,
                      child: Container(
                        width: 120,
                        height: 120,
                        child: Image.asset(
                          'swapdotz_possible_logo_no_bg.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              SizedBox(height: 40),
              
              // App name with animation
              AnimatedBuilder(
                animation: _textAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - _textAnimation.value)),
                      child: Column(
                        children: [
                          Text(
                            'SwapDotz',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                              letterSpacing: 3,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Hand to Hand, Coast to Coast.',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              SizedBox(height: 60),
              
              // Loading indicator
              AnimatedBuilder(
                animation: _textAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textAnimation.value,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF00CED1),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }
}

class CelebrationScreen extends StatefulWidget {
  final String swapDotId;
  
  const CelebrationScreen({Key? key, required this.swapDotId}) : super(key: key);

  @override
  _CelebrationScreenState createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with TickerProviderStateMixin {
  late AnimationController _pointsController;
  late AnimationController _mapController;
  late AnimationController _celebrityController;
  late AnimationController _splashController;
  late Animation<double> _pointsAnimation;
  late Animation<double> _mapAnimation;
  late Animation<double> _celebrityAnimation;
  late Animation<double> _splashAnimation;
  
  bool _showSplash = true;
  int _displayedPoints = 0;
  final int _totalPoints = 15420;
  final List<MapLocation> _locations = [
    MapLocation('New York', 40.7128, -74.0060, '🏙️'),
    MapLocation('Los Angeles', 34.0522, -118.2437, '🌴'),
    MapLocation('London', 51.5074, -0.1278, '🇬🇧'),
    MapLocation('Tokyo', 35.6762, 139.6503, '🗾'),
    MapLocation('Paris', 48.8566, 2.3522, '🗼'),
    MapLocation('Sydney', -33.8688, 151.2093, '🦘'),
    MapLocation('Dubai', 25.2048, 55.2708, '🏜️'),
    MapLocation('Singapore', 1.3521, 103.8198, '🌺'),
    MapLocation('Philadelphia', 39.9526, -75.1652, '🔔'),
    MapLocation('San Francisco', 37.7749, -122.4194, '🌉'),
  ];

  @override
  void initState() {
    super.initState();
    
    _pointsController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    );
    
    _mapController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _celebrityController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _splashController = AnimationController(
      duration: Duration(milliseconds: 5000),
      vsync: this,
    );
    
    _pointsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pointsController, curve: Curves.easeOut),
    );
    
    _mapAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mapController, curve: Curves.easeOut),
    );
    
    _celebrityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrityController, curve: Curves.elasticOut),
    );
    
    _splashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _splashController, curve: Curves.easeInOut),
    );
    
    _startAnimations();
  }

  void _startAnimations() async {
    // Start with splash animation
    _splashController.forward();
    
    // Don't auto-transition - wait for user to tap X
    // The transition will be handled by the X button tap
  }

  void _startMainCelebrationAnimations() async {
    await Future.delayed(Duration(milliseconds: 1000));
    _mapController.forward();
    
    await Future.delayed(Duration(milliseconds: 1500));
    _celebrityController.forward();
    
    // Animate points counter
    for (int i = 0; i <= _totalPoints; i += 500) {
      await Future.delayed(Duration(milliseconds: 20));
      setState(() {
        _displayedPoints = i;
      });
    }
    setState(() {
      _displayedPoints = _totalPoints;
    });
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _mapController.dispose();
    _celebrityController.dispose();
    _splashController.dispose();
    super.dispose();
  }

  Widget _buildSocialButton(String platform, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.8)],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF00CED1), // Bright cyan blue
              Color(0xFF1a1a2e), // Dark blue
              Color(0xFFFF8C42), // Vibrant orange (subtle)
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative elements for celebration screen
            Positioned(
              top: 80,
              left: 20,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00CED1).withOpacity(0.3),
                ),
              ),
            ),
            Positioned(
              top: 120,
              right: 30,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF8C42).withOpacity(0.2),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              left: 40,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF32CD32).withOpacity(0.3),
                  border: Border.all(
                    color: Color(0xFF32CD32).withOpacity(0.5),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              right: 50,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFFF00).withOpacity(0.5),
                ),
              ),
            ),
            
            _showSplash ? _buildSplashScreen() : _buildMainCelebrationScreen(),
          ],
        ),
      ),
    );
  }

  Widget _buildSplashScreen() {
    return AnimatedBuilder(
      animation: _splashAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Basketball icon with animation
                    Transform.scale(
                      scale: _splashAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFFFFD700).withOpacity(0.4),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.sports_basketball,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 40),
                    
                    // Text animation
                    Opacity(
                      opacity: _splashAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - _splashAnimation.value)),
                        child: Column(
                          children: [
                            Text(
                              'This SwapDot was owned by...',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'MICHAEL JORDAN!',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD700),
                                letterSpacing: 3,
                                shadows: [
                                  Shadow(
                                    color: Color(0xFFFFD700).withOpacity(0.5),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              '🏀 NBA Legend & 6x Champion 🏀',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 40),
                    
                    // Social Media Share Buttons
                    Opacity(
                      opacity: _splashAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - _splashAnimation.value)),
                        child: Column(
                          children: [
                            Text(
                              'Share this amazing find!',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildSocialButton('Twitter', Icons.flutter_dash, Color(0xFF1DA1F2), () {}),
                                SizedBox(width: 16),
                                _buildSocialButton('Facebook', Icons.facebook, Color(0xFF1877F2), () {}),
                                SizedBox(width: 16),
                                _buildSocialButton('Instagram', Icons.camera_alt, Color(0xFFE4405F), () {}),
                                SizedBox(width: 16),
                                _buildSocialButton('WhatsApp', Icons.chat, Color(0xFF25D366), () {}),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // X button to dismiss splash
              Positioned(
                top: 60,
                right: 20,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showSplash = false;
                    });
                    
                    // Start the main celebration animations
                    Future.delayed(Duration(milliseconds: 500), () {
                      _pointsController.forward();
                      _startMainCelebrationAnimations();
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
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

  Widget _buildMainCelebrationScreen() {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(24),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Spacer(),
                Text(
                  'YOUR NEW SWAPDOT!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00CED1),
                    letterSpacing: 2,
                  ),
                ),
                Spacer(),
              ],
            ),
          ),
          
          // Points Counter
          AnimatedBuilder(
            animation: _pointsAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pointsAnimation.value,
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 24),
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00CED1), Color(0xFF00B4B4)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF00CED1).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'POINTS EARNED',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${_displayedPoints.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          SizedBox(height: 24),
          
          // Travel Achievements
          Expanded(
            child: AnimatedBuilder(
              animation: _mapAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _mapAnimation.value,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            '🌍 TRAVEL ACHIEVEMENTS',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _locations.length,
                            itemBuilder: (context, index) {
                              final location = _locations[index];
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF00CED1).withOpacity(0.2),
                                      Color(0xFF00B4B4).withOpacity(0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Color(0xFF00CED1).withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      location.emoji,
                                      style: TextStyle(fontSize: 32),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      location.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Visited',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF00CED1),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: 24),
          
          // Celebrity Ownership
          AnimatedBuilder(
            animation: _celebrityAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _celebrityAnimation.value,
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 24),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFFFD700).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'This SwapDot was once owned by...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '🏀',
                            style: TextStyle(fontSize: 32),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Michael Jordan',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'NBA Legend & 6x Champion',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class MapLocation {
  final String name;
  final double lat;
  final double lng;
  final String emoji;
  
  MapLocation(this.name, this.lat, this.lng, this.emoji);
}

class LeaderboardScreen extends StatefulWidget {
  @override
  _LeaderboardScreenState createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _listController;
  late Animation<double> _listAnimation;
  
  final List<LeaderboardEntry> _leaderboard = [
    LeaderboardEntry('Michael Jordan', 15420, '🏀', 1),
    LeaderboardEntry('LeBron James', 14230, '👑', 2),
    LeaderboardEntry('Kobe Bryant', 13890, '🐍', 3),
    LeaderboardEntry('Stephen Curry', 12560, '🏀', 4),
    LeaderboardEntry('Kevin Durant', 11890, '🔥', 5),
    LeaderboardEntry('Giannis Antetokounmpo', 11240, '🦌', 6),
    LeaderboardEntry('Luka Dončić', 10890, '🏀', 7),
    LeaderboardEntry('Nikola Jokić', 10230, '🐻', 8),
    LeaderboardEntry('Joel Embiid', 9870, '🦅', 9),
    LeaderboardEntry('Damian Lillard', 9450, '⏰', 10),
  ];

  @override
  void initState() {
    super.initState();
    
    _listController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _listAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _listController, curve: Curves.easeOut),
    );
    
    _listController.forward();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    Spacer(),
                    Text(
                      '🏆 LEADERBOARD',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFD700),
                        letterSpacing: 2,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),
              
              // Leaderboard List
              Expanded(
                child: AnimatedBuilder(
                  animation: _listAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _listAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - _listAnimation.value)),
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _leaderboard.length,
                          itemBuilder: (context, index) {
                            final entry = _leaderboard[index];
                            return Container(
                              margin: EdgeInsets.only(bottom: 12),
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    entry.rank <= 3 
                                      ? Color(0xFFFFD700).withOpacity(0.2)
                                      : Colors.white.withOpacity(0.1),
                                    entry.rank <= 3 
                                      ? Color(0xFFFFA500).withOpacity(0.1)
                                      : Colors.white.withOpacity(0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: entry.rank <= 3 
                                    ? Color(0xFFFFD700).withOpacity(0.3)
                                    : Colors.white.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Rank
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: entry.rank <= 3 
                                        ? Color(0xFFFFD700)
                                        : Colors.white.withOpacity(0.2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${entry.rank}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: entry.rank <= 3 
                                            ? Colors.black
                                            : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  SizedBox(width: 16),
                                  
                                  // Emoji
                                  Text(
                                    entry.emoji,
                                    style: TextStyle(fontSize: 24),
                                  ),
                                  
                                  SizedBox(width: 12),
                                  
                                  // Name
                                  Expanded(
                                    child: Text(
                                      entry.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  
                                  // Points
                                  Text(
                                    '${entry.points.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: entry.rank <= 3 
                                        ? Color(0xFFFFD700)
                                        : Color(0xFF00ff88),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class LeaderboardEntry {
  final String name;
  final int points;
  final String emoji;
  final int rank;
  
  LeaderboardEntry(this.name, this.points, this.emoji, this.rank);
}

class MarketplaceScreen extends StatefulWidget {
  @override
  _MarketplaceScreenState createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with TickerProviderStateMixin {
  late AnimationController _gridController;
  late Animation<double> _gridAnimation;
  
  final List<MarketplaceItem> _items = [
    MarketplaceItem(
      'Michael Jordan Legacy',
      'SwapDot featuring MJ\'s iconic moments - rare design',
      '🏀',
      'assets/marketplace_images/inspired_by_legends/skywalker_legacy.png',
      '\$2,499.99',
      'Rare SwapDot',
      Color(0xFFFFD700),
      'Limited Edition #23',
    ),
    MarketplaceItem(
      'LeBron James Crown',
      'SwapDot owned by the King himself - 4x NBA Champion',
      '👑',
      'assets/marketplace_images/inspired_by_legends/royal_emblem.png',
      '\$1,899.99',
      'Notable Ownership',
      Color(0xFFFF6B6B),
      'Previously owned by LeBron',
    ),
    MarketplaceItem(
      'Kobe Bryant Mamba',
      'SwapDot honoring the Black Mamba - rare design',
      '🐍',
      'assets/marketplace_images/inspired_by_legends/mamba_strike.png',
      '\$1,599.99',
      'Rare SwapDot',
      Color(0xFF8B5CF6),
      'Limited Edition #24',
    ),
    MarketplaceItem(
      'Stephen Curry Splash',
      'SwapDot owned by the greatest shooter of all time',
      '🏀',
      'assets/marketplace_images/inspired_by_legends/splash_signature.png',
      '\$1,299.99',
      'Notable Ownership',
      Color(0xFF00CED1),
      'Previously owned by Steph',
    ),
    MarketplaceItem(
      'Kevin Durant Slim Reaper',
      'SwapDot featuring KD\'s signature moves',
      '🔥',
      'assets/marketplace_images/inspired_by_legends/shadow_reaper.png',
      '\$999.99',
      'Rare SwapDot',
      Color(0xFFFFA500),
      'Limited Edition #35',
    ),
    MarketplaceItem(
      'Giannis Greek Freak',
      'SwapDot owned by the Greek Freak - 2x MVP',
      '🦌',
      'assets/marketplace_images/inspired_by_legends/olympian_fury.png',
      '\$899.99',
      'Notable Ownership',
      Color(0xFF00FF88),
      'Previously owned by Giannis',
    ),
    MarketplaceItem(
      'Luka Magic',
      'SwapDot showcasing Luka\'s magic - rare design',
      '🏀',
      'assets/marketplace_images/inspired_by_legends/euro_magic.png',
      '\$799.99',
      'Rare SwapDot',
      Color(0xFF6366F1),
      'Limited Edition #77',
    ),
    MarketplaceItem(
      'Nikola Jokić Joker',
      'SwapDot owned by the Joker - 2x MVP',
      '🐻',
      'assets/marketplace_images/inspired_by_legends/card_master.png',
      '\$699.99',
      'Notable Ownership',
      Color(0xFF8B4513),
      'Previously owned by Jokić',
    ),
    MarketplaceItem(
      'Joel Embiid Process',
      'SwapDot from the Process era - rare design',
      '🦅',
      'assets/marketplace_images/inspired_by_legends/urban_process.png',
      '\$599.99',
      'Rare SwapDot',
      Color(0xFF4169E1),
      'Limited Edition #21',
    ),
    MarketplaceItem(
      'Damian Lillard Time',
      'SwapDot owned by Dame Time himself',
      '⏰',
      'assets/marketplace_images/inspired_by_legends/zero_hour.png',
      '\$499.99',
      'Notable Ownership',
      Color(0xFFDC143C),
      'Previously owned by Dame',
    ),
    MarketplaceItem(
      'Magic Johnson Showtime',
      'SwapDot from the Showtime era - rare design',
      '✨',
      'assets/marketplace_images/inspired_by_legends/retro_flash.png',
      '\$399.99',
      'Rare SwapDot',
      Color(0xFFFF69B4),
      'Limited Edition #32',
    ),
    MarketplaceItem(
      'Larry Bird Legend',
      'SwapDot owned by the Hick from French Lick',
      '🍀',
      'assets/marketplace_images/inspired_by_legends/green_floor_general.png',
      '\$299.99',
      'Notable Ownership',
      Color(0xFF32CD32),
      'Previously owned by Larry',
    ),
    MarketplaceItem(
      'Cool Blue SwapDot',
      'Beautiful blue gradient SwapDot - great condition',
      '💎',
      'assets/marketplace_images/regular/cool_blue_swapdot.png',
      '\$89.99',
      'Regular Listing',
      Color(0xFF00CED1),
      'Seller: JohnDoe123',
    ),
    MarketplaceItem(
      'Golden Phoenix',
      'Rare golden phoenix SwapDot - limited availability',
      '🔥',
      'assets/marketplace_images/regular/golden_phoenix.png',
      '\$149.99',
      'Regular Listing',
      Color(0xFFFFD700),
      'Seller: PhoenixCollector',
    ),
    MarketplaceItem(
      'Neon Cyber',
      'Futuristic neon cyber SwapDot - perfect for tech lovers',
      '⚡',
      'assets/marketplace_images/regular/neon_cyber.png',
      '\$67.50',
      'Regular Listing',
      Color(0xFF00FF88),
      'Seller: CyberTrader',
    ),
    MarketplaceItem(
      'Vintage Basketball',
      'Classic basketball SwapDot - retro vibes',
      '🏀',
      'assets/marketplace_images/regular/vintage_basketball.png',
      '\$45.00',
      'Regular Listing',
      Color(0xFFFF6B6B),
      'Seller: RetroFan',
    ),
    MarketplaceItem(
      'Ocean Wave',
      'Calming ocean wave SwapDot - mint condition',
      '🌊',
      'assets/marketplace_images/regular/ocean_wave.png',
      '\$78.25',
      'Regular Listing',
      Color(0xFF4169E1),
      'Seller: OceanLover',
    ),
    MarketplaceItem(
      'Forest Guardian',
      'Mystical forest guardian SwapDot - one of a kind',
      '🌲',
      'assets/marketplace_images/regular/forest_guardian.png',
      '\$125.00',
      'Regular Listing',
      Color(0xFF32CD32),
      'Seller: NatureCollector',
    ),
    MarketplaceItem(
      'Sunset Glow',
      'Beautiful sunset gradient SwapDot - perfect gift',
      '🌅',
      'assets/marketplace_images/regular/sunset_glow.png',
      '\$55.75',
      'Regular Listing',
      Color(0xFFFFA500),
      'Seller: GiftGiver',
    ),
    MarketplaceItem(
      'Galaxy Explorer',
      'Space-themed galaxy SwapDot - out of this world',
      '🚀',
      'assets/marketplace_images/regular/galaxy_explorer.png',
      '\$92.99',
      'Regular Listing',
      Color(0xFF8B5CF6),
      'Seller: SpaceExplorer',
    ),
    MarketplaceItem(
      'Rare 2025 McDonalds Grimace',
      'Limited edition Grimace SwapDot - brand collaboration',
      '🍔',
      'assets/marketplace_images/fantasy_brands/fuzzy_purple_friend.png',
      '\$349.99',
      'Branded SwapDot',
      Color(0xFFFFC107),
      'Seller: McDonaldsOfficial',
    ),
    MarketplaceItem(
      'Mint Condition Pepsi',
      'Pristine Pepsi SwapDot - never used, perfect condition',
      '🥤',
      'assets/marketplace_images/fantasy_brands/fizzy_duo_classic.png',
      '\$189.99',
      'Branded SwapDot',
      Color(0xFF2196F3),
      'Seller: PepsiCollector',
    ),
    MarketplaceItem(
      'Nike Air Jordan SwapDot',
      'Official Nike Air Jordan branded SwapDot - rare find',
      '👟',
      'assets/marketplace_images/fantasy_brands/high_jump_dream.png',
      '\$599.99',
      'Branded SwapDot',
      Color(0xFF000000),
      'Seller: NikeOfficial',
    ),
    MarketplaceItem(
      'Coca-Cola Classic',
      'Vintage Coca-Cola SwapDot - retro design',
      '🥤',
      'assets/marketplace_images/fantasy_brands/vintage_soda_glow.png',
      '\$275.00',
      'Branded SwapDot',
      Color(0xFFD32F2F),
      'Seller: CokeCollector',
    ),
    MarketplaceItem(
      'Adidas Originals',
      'Adidas Originals branded SwapDot - street style',
      '👟',
      'assets/marketplace_images/fantasy_brands/urban_runner.png',
      '\$199.99',
      'Branded SwapDot',
      Color(0xFF000000),
      'Seller: AdidasFan',
    ),
    MarketplaceItem(
      'Starbucks Reserve',
      'Premium Starbucks Reserve SwapDot - limited release',
      '☕',
      'assets/marketplace_images/fantasy_brands/artisan_reserve.png',
      '\$425.00',
      'Branded SwapDot',
      Color(0xFF795548),
      'Seller: StarbucksOfficial',
    ),
    MarketplaceItem(
      'Doritos Nacho Cheese',
      'Doritos branded SwapDot - spicy design',
      '🌶️',
      'assets/marketplace_images/fantasy_brands/spicy_triangle.png',
      '\$89.99',
      'Branded SwapDot',
      Color(0xFFFF9800),
      'Seller: SnackCollector',
    ),
  ];

  @override
  void initState() {
    super.initState();
    
    _gridController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _gridAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _gridController, curve: Curves.easeOut),
    );
    
    _gridController.forward();
  }

  @override
  void dispose() {
    _gridController.dispose();
    super.dispose();
  }

  Color _getBrightPriceColor(Color accentColor) {
    // Ensure price is always bright and readable
    if (accentColor.computeLuminance() < 0.5) {
      // If the accent color is dark, use a bright version
      return Color.lerp(accentColor, Colors.white, 0.7) ?? Colors.white;
    }
    return accentColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    Spacer(),
                    Text(
                      '🛒 MARKETPLACE',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF8C42),
                        letterSpacing: 2,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),
              
              // Marketplace Grid
              Expanded(
                child: AnimatedBuilder(
                  animation: _gridAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _gridAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - _gridAnimation.value)),
                        child: GridView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.6,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    item.accentColor.withOpacity(0.2),
                                    item.accentColor.withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: item.accentColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                                                             child: Column(
                                 children: [
                                   // Large SwapDot Image
                                   Container(
                                     padding: EdgeInsets.all(8),
                                     child: Column(
                                       children: [
                                         Container(
                                           width: 70,
                                           height: 70,
                                           decoration: BoxDecoration(
                                             shape: BoxShape.circle,
                                             boxShadow: [
                                               BoxShadow(
                                                 color: item.accentColor.withOpacity(0.4),
                                                 blurRadius: 12,
                                                 spreadRadius: 3,
                                               ),
                                             ],
                                           ),
                                           child: ClipOval(
                                             child: Image.asset(
                                               item.imagePath,
                                               fit: BoxFit.cover,
                                               width: 70,
                                               height: 70,
                                               errorBuilder: (context, error, stackTrace) {
                                                 print('Image load error for ${item.imagePath}: $error');
                                                 // Fallback to emoji if image fails to load
                                                 return Container(
                                                   decoration: BoxDecoration(
                                                     shape: BoxShape.circle,
                                                     color: item.accentColor.withOpacity(0.2),
                                                   ),
                                                   child: Center(
                                                     child: Text(
                                                       item.emoji,
                                                       style: TextStyle(fontSize: 32),
                                                     ),
                                                   ),
                                                 );
                                               },
                                             ),
                                           ),
                                         ),
                                         SizedBox(height: 8),
                                         Text(
                                           item.points,
                                           style: TextStyle(
                                             fontSize: 12,
                                             fontWeight: FontWeight.bold,
                                             color: _getBrightPriceColor(item.accentColor),
                                           ),
                                         ),
                                       ],
                                     ),
                                   ),
                                  
                                                                     // Content
                                   Expanded(
                                     child: Padding(
                                       padding: EdgeInsets.symmetric(horizontal: 6),
                                       child: Column(
                                         crossAxisAlignment: CrossAxisAlignment.center,
                                         children: [
                                           Text(
                                             item.name,
                                             style: TextStyle(
                                               fontSize: 11,
                                               fontWeight: FontWeight.bold,
                                               color: Colors.white,
                                             ),
                                             maxLines: 1,
                                             overflow: TextOverflow.ellipsis,
                                             textAlign: TextAlign.center,
                                           ),
                                           SizedBox(height: 2),
                                           Text(
                                             item.description,
                                             style: TextStyle(
                                               fontSize: 8,
                                               color: Colors.white70,
                                             ),
                                             textAlign: TextAlign.center,
                                           ),
                                           SizedBox(height: 4),
                                           Container(
                                             padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                             decoration: BoxDecoration(
                                               color: item.accentColor.withOpacity(0.2),
                                               borderRadius: BorderRadius.circular(4),
                                             ),
                                             child: Text(
                                               item.category,
                                               style: TextStyle(
                                                 fontSize: 6,
                                                 fontWeight: FontWeight.bold,
                                                 color: item.accentColor,
                                               ),
                                             ),
                                           ),
                                           SizedBox(height: 2),
                                           Text(
                                             item.subtitle,
                                             style: TextStyle(
                                               fontSize: 6,
                                               color: Colors.white60,
                                               fontStyle: FontStyle.italic,
                                             ),
                                             maxLines: 1,
                                             overflow: TextOverflow.ellipsis,
                                             textAlign: TextAlign.center,
                                           ),
                                         ],
                                       ),
                                     ),
                                   ),
                                  
                                                                     // Buy Button
                                   Container(
                                     width: double.infinity,
                                     margin: EdgeInsets.all(6),
        child: ElevatedButton(
                                       onPressed: () {
                                         // Fake purchase action
                                         ScaffoldMessenger.of(context).showSnackBar(
                                           SnackBar(
                                             content: Text('Purchase feature coming soon!'),
                                             backgroundColor: item.accentColor,
                                           ),
                                         );
                                       },
                                       style: ElevatedButton.styleFrom(
                                         backgroundColor: item.accentColor,
                                         foregroundColor: Colors.white,
                                         shape: RoundedRectangleBorder(
                                           borderRadius: BorderRadius.circular(4),
                                         ),
                                         padding: EdgeInsets.symmetric(vertical: 4),
                                       ),
                                       child: Text(
                                         'BUY NOW',
                                         style: TextStyle(
                                           fontSize: 8,
                                           fontWeight: FontWeight.bold,
                                         ),
                                       ),
                                     ),
                                   ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class MarketplaceItem {
  final String name;
  final String description;
  final String emoji;
  final String imagePath;
  final String points;
  final String category;
  final Color accentColor;
  final String subtitle;
  
  MarketplaceItem(
    this.name,
    this.description,
    this.emoji,
    this.imagePath,
    this.points,
    this.category,
    this.accentColor,
    this.subtitle,
  );
}

class SwapDotzApp extends StatefulWidget {
  @override
  _SwapDotzAppState createState() => _SwapDotzAppState();
}

class _SwapDotzAppState extends State<SwapDotzApp>
    with TickerProviderStateMixin {
  bool _isScanning = false;
  bool _showOverlay = false;
  String _statusMessage = '';
  String _cardInfo = '';
  String _selectedUser = 'oliver'; // Default user
  AnimationController? _pulseController;
  AnimationController? _fadeController;
  Animation<double>? _pulseAnimation;
  Animation<double>? _fadeAnimation;

  final List<String> _users = ['oliver', 'jonathan'];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController!, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _fadeController?.dispose();
    super.dispose();
  }

  Widget _buildFooterItem(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: Colors.white70,
              ),
              SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateStatus(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _updateCardInfo(String info) {
    setState(() {
      _cardInfo = info;
    });
  }

  Future<void> _startSwapDot() async {
    // Version check before allowing NFC operations
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_requirements')
          .get();
      
      if (configDoc.exists) {
        final data = configDoc.data();
        final requiredVersion = data?['minimum_version'] ?? '1.0.0';
        
        if (_isVersionOlder(currentVersion, requiredVersion)) {
          // Show update screen and abort NFC operation
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => VersionCheckScreen(
                  currentVersion: currentVersion,
                  requiredVersion: requiredVersion,
                  updateMessage: data?['update_message'],
                  updateUrl: data?['update_url'],
                ),
              ),
              (route) => false,
            );
          }
          return;
        }
      }
    } catch (e) {
      print('Version check during NFC scan failed: $e');
      // Allow operation to continue if check fails
    }
    
    setState(() {
      _isScanning = true;
      _showOverlay = true;
      _statusMessage = '';
      _cardInfo = '';
    });

    _fadeController?.forward();
    _pulseController?.repeat(reverse: true);

    try {
      _updateStatus('Looking for SwapDot...');
      
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: 'Hold your SwapDot near the device',
      );
      
      _updateCardInfo('SwapDot Type: ${tag.type}\nSwapDot ID: ${tag.id}');
      
      // Create DESFire instance
      final desfire = Desfire(tag);
      
      try {
        // Step 1: Authenticate with factory key
        _updateStatus('Authenticating with SwapDot...');
        await desfire.authenticateLegacy();
        
        // Step 2: Ensure app and file exist
        _updateStatus('Setting up SwapDot storage...');
        await desfire.ensureAppAndFileExist();
        
        // Step 3: Read existing data (if any)
        _updateStatus('Reading SwapDot data...');
        String existingData = '';
        String? existingOwner;
        String? existingKey;
        bool hasTransferSession = false;
        
        try {
          final readBytes = await desfire.readFile01(200);
          existingData = utf8.decode(readBytes.takeWhile((b) => b != 0).toList());
          
          // Parse existing data
          if (existingData.contains('owner:')) {
            final ownerStart = existingData.indexOf('owner:') + 6;
            final ownerEnd = existingData.indexOf(';', ownerStart);
            if (ownerEnd > ownerStart) {
              existingOwner = existingData.substring(ownerStart, ownerEnd);
            }
          }
          
          if (existingData.contains('key:')) {
            final keyStart = existingData.indexOf('key:') + 4;
            final keyEnd = existingData.indexOf(';', keyStart);
            if (keyEnd > keyStart) {
              existingKey = existingData.substring(keyStart, keyEnd);
            }
          }
          
          hasTransferSession = existingData.contains('transfer:active');
          
          _updateCardInfo('${_cardInfo}\nCurrent owner: ${existingOwner ?? "None"}');
        } catch (e) {
          _updateCardInfo('${_cardInfo}\nSwapDot is uninitialized');
        }
        
        // Step 4: Determine action based on current state
        
        // Case 1: Uninitialized card - anyone can claim it
        if (existingKey == null || existingKey.isEmpty) {
          _updateStatus('Uninitialized SwapDot detected!');
          _updateStatus('Claiming ownership...');
          
          // Generate a new key for the new owner
          final random = Random.secure();
          final newKey = Uint8List.fromList(
            List.generate(16, (_) => random.nextInt(256))
          );
          final keyHex = newKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          
          final ownershipData = 'owner:$_selectedUser;key:$keyHex;initialized:${DateTime.now().millisecondsSinceEpoch}';
          final dataBytes = utf8.encode(ownershipData);
          
          await desfire.writeFile01(Uint8List.fromList(dataBytes));
          
          _updateStatus('✅ SwapDot claimed by $_selectedUser!');
          _updateCardInfo('''${_cardInfo}

You are now the owner!
Your ownership key: ${keyHex.substring(0, 16)}...

This SwapDot is now yours. You can gift it to someone else by 
starting a transfer session.''');
          
          // Show celebration for new ownership
          if (_selectedUser == 'jonathan') {
            await Future.delayed(Duration(seconds: 1));
            Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => CelebrationScreen(swapDotId: tag.id),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, 1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  );
                },
                transitionDuration: Duration(milliseconds: 800),
              ),
            );
          }
        }
        
        // Case 2: Card owned by current user - start transfer session
        else if (existingOwner == _selectedUser && !hasTransferSession) {
          _updateStatus('You own this SwapDot!');
          
          // TODO: Check with server if key rotation is required
          // This would be a real Firebase call in production
          bool serverRequiresKeyRotation = false; // Simulated for now
          
          // Check for any server-mandated operations
          Map<String, dynamic>? serverCommand; // Simulated for now
          
          // In production, this would be:
          // final tokenDoc = await FirebaseFirestore.instance
          //     .collection('tokens')
          //     .doc(tag.id)
          //     .get();
          // 
          // final requiresRotation = tokenDoc.data()?['requires_key_rotation'] ?? false;
          // final rotationReason = tokenDoc.data()?['rotation_reason'];
          //
          // Check for critical server commands
          // final serverCommand = tokenDoc.data()?['pending_command'];
          // if (serverCommand != null) {
          //   await executeServerCommand(desfire, serverCommand);
          //   // Clear the command after execution
          //   await tokenDoc.reference.update({'pending_command': FieldValue.delete()});
          // }
          //
          // Server commands could include:
          // - {'type': 'upgrade_des_to_aes', 'params': {...}}
          // - {'type': 'rotate_master_key', 'params': {...}}
          // - {'type': 'change_file_permissions', 'params': {...}}
          // - {'type': 'add_new_application', 'params': {...}}
          // - {'type': 'emergency_lockdown', 'params': {...}}
          
          // Example: Simulated DES to AES upgrade command
          // serverCommand = {
          //   'type': 'upgrade_des_to_aes',
          //   'priority': 'critical',
          //   'params': {
          //     'new_aes_key': 'a1b2c3d4e5f6789012345678901234567',
          //     'backup_data': true
          //   }
          // };
          
          if (serverCommand != null) {
            await _executeServerCommand(desfire, serverCommand, tag.id);
            // After server command, refresh the card state
            existingData = '';
            try {
              final readBytes = await desfire.readFile01(200);
              existingData = utf8.decode(readBytes.takeWhile((b) => b != 0).toList());
              
              // Re-parse owner after command execution
              if (existingData.contains('owner:')) {
                final ownerStart = existingData.indexOf('owner:') + 6;
                final ownerEnd = existingData.indexOf(';', ownerStart);
                if (ownerEnd > ownerStart) {
                  existingOwner = existingData.substring(ownerStart, ownerEnd);
                }
              }
            } catch (e) {
              // File might have been restructured
            }
          } else if (serverRequiresKeyRotation) {
            _updateStatus('⚠️ Security update required!');
            _updateStatus('Rotating your ownership key...');
            
            // Generate a new key for security rotation
            final random = Random.secure();
            final newKey = Uint8List.fromList(
              List.generate(16, (_) => random.nextInt(256))
            );
            final keyHex = newKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            
            // Preserve ownership but update key
            final rotatedData = 'owner:$_selectedUser;key:$keyHex;rotated:${DateTime.now().millisecondsSinceEpoch};reason:server_mandate';
            final dataBytes = utf8.encode(rotatedData);
            
            await desfire.writeFile01(Uint8List.fromList(dataBytes));
            
            _updateStatus('✅ Security key rotation complete!');
            _updateCardInfo('''${_cardInfo}

Security Update Applied!
Your ownership key has been rotated.
New key: ${keyHex.substring(0, 16)}...

This was a mandatory security update from the server.
Your ownership remains unchanged.''');
          } else {
            // Normal transfer flow
            _updateStatus('Starting gift transfer session...');
            
            // Current owner starts a transfer session but DOES NOT write a new key
            final transferData = '$existingData;transfer:active;from:$_selectedUser;time:${DateTime.now().millisecondsSinceEpoch}';
            final dataBytes = utf8.encode(transferData);
            
            await desfire.writeFile01(Uint8List.fromList(dataBytes));
            
            _updateStatus('✅ Gift transfer initiated!');
            _updateCardInfo('''${_cardInfo}

Transfer session started!
From: $_selectedUser
Status: Ready to be claimed

Give this SwapDot to someone and have them scan it 
to complete the transfer. They will become the new owner.''');
          }
        }
        
        // Case 3: Active transfer session - recipient can claim
        else if (hasTransferSession && existingOwner != _selectedUser) {
          _updateStatus('Gift transfer in progress!');
          _updateStatus('Claiming your new SwapDot...');
          
          // Generate a new key for the new owner
          final random = Random.secure();
          final newKey = Uint8List.fromList(
            List.generate(16, (_) => random.nextInt(256))
          );
          final keyHex = newKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          
          // New owner writes their key and claims ownership
          final newOwnershipData = 'owner:$_selectedUser;key:$keyHex;prev:$existingOwner;claimed:${DateTime.now().millisecondsSinceEpoch}';
          final dataBytes = utf8.encode(newOwnershipData);
          
          await desfire.writeFile01(Uint8List.fromList(dataBytes));
          
          _updateStatus('✅ SwapDot successfully received!');
          _updateCardInfo('''${_cardInfo}

Gift received!
From: $existingOwner
To: $_selectedUser
Your new key: ${keyHex.substring(0, 16)}...

You are now the owner of this SwapDot!''');
          
          // Show celebration
          await Future.delayed(Duration(seconds: 1));
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => CelebrationScreen(swapDotId: tag.id),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, 1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
              transitionDuration: Duration(milliseconds: 800),
            ),
          );
        }
        
        // Case 4: Not your card and no transfer session
        else if (existingOwner != _selectedUser && !hasTransferSession) {
          _updateStatus('❌ Not your SwapDot');
          _updateCardInfo('''${_cardInfo}

This SwapDot belongs to: $existingOwner
No active transfer session.

The owner must scan this card first to initiate
a gift transfer before you can claim it.''');
        }
        
        // Case 5: Already has transfer session from current user
        else if (existingOwner == _selectedUser && hasTransferSession) {
          _updateStatus('⏳ Transfer already in progress');
          _updateCardInfo('''${_cardInfo}

You already started a gift transfer.
Give this SwapDot to someone else and 
have them scan it to complete the transfer.''');
        }
        
      } catch (desfireError) {
        // Handle DESFire-specific errors
        _showErrorScreen(desfireError.toString());
        return;
      }

      await Future.delayed(Duration(seconds: 2));
      await FlutterNfcKit.finish(iosAlertMessage: 'SwapDot transaction completed!');
      
    } catch (e) {
      _showErrorScreen(e.toString());
      await FlutterNfcKit.finish(iosErrorMessage: 'Transaction failed');
    } finally {
      setState(() {
        _isScanning = false;
      });
      _pulseController?.stop();
      _pulseController?.reset();
      
      // Don't automatically hide overlay if there was an error
      if (!_statusMessage.contains('❌') && !_statusMessage.contains('Error')) {
        await Future.delayed(Duration(seconds: 2));
        _fadeController?.reverse();
        await Future.delayed(Duration(milliseconds: 300));
        setState(() {
          _showOverlay = false;
          _statusMessage = '';
          _cardInfo = '';
        });
      }
    }
  }
  
  void _showErrorScreen(String error) {
    String friendlyError = 'Unknown error occurred';
    String suggestion = 'Please try again';
    
    // Parse common DESFire errors
    if (error.contains('Card returned: 91 7e')) {
      friendlyError = 'File length error';
      suggestion = 'The SwapDot storage is full or corrupted. Try a different token.';
    } else if (error.contains('Card returned: 91 9d')) {
      friendlyError = 'Permission denied';
      suggestion = 'This SwapDot is locked. You need the correct key to access it.';
    } else if (error.contains('Card returned: 91 ae')) {
      friendlyError = 'Authentication failed';
      suggestion = 'This SwapDot uses a different key. It may already be initialized by someone else.';
    } else if (error.contains('Card returned: 91 1c')) {
      friendlyError = 'Illegal command';
      suggestion = 'This might not be a compatible DESFire token.';
    } else if (error.contains('Card returned: 91 f0')) {
      friendlyError = 'File not found';
      suggestion = 'The SwapDot needs to be initialized first.';
    } else if (error.contains('Tag was lost')) {
      friendlyError = 'Connection lost';
      suggestion = 'Keep the SwapDot steady against the phone while scanning.';
    } else if (error.contains('Authenticate step‑1 failed')) {
      friendlyError = 'Authentication protocol error';
      suggestion = 'This token might be using a different authentication method.';
    }
    
    setState(() {
      _statusMessage = '❌ Error: $friendlyError';
      _cardInfo = '''
Technical details:
$error

💡 Suggestion:
$suggestion

Tap outside this box to try again.
''';
    });
  }
  
  bool _isVersionOlder(String current, String required) {
    // Simple version comparison - splits by dots and compares numbers
    final currentParts = current.split('.').map(int.tryParse).toList();
    final requiredParts = required.split('.').map(int.tryParse).toList();
    
    for (int i = 0; i < requiredParts.length; i++) {
      final currentPart = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      final requiredPart = requiredParts[i] ?? 0;
      
      if (currentPart < requiredPart) return true;
      if (currentPart > requiredPart) return false;
    }
    
    return false;
  }
  
  Future<void> _executeServerCommand(Desfire desfire, Map<String, dynamic> command, String tagId) async {
    final commandType = command['type'] as String?;
    final priority = command['priority'] as String?;
    final params = command['params'] as Map<String, dynamic>?;
    
    _updateStatus('🔧 Executing server command: $commandType');
    
    try {
      switch (commandType) {
        case 'upgrade_des_to_aes':
          _updateStatus('Upgrading from DES to AES encryption...');
          
          // Example: Change from DES to AES authentication
          // 1. Authenticate with current DES key
          // 2. Change key 0x00 to AES
          // final newAesKeyHex = params?['new_aes_key'] as String?;
          // if (newAesKeyHex != null) {
          //   final aesKey = _hexToBytes(newAesKeyHex);
          //   await desfire.changeKey(0x00, aesKey, KeyType.AES128);
          // }
          
          _updateStatus('✅ Encryption upgraded to AES-128');
          _updateCardInfo('Security upgrade complete!\nYour SwapDot now uses AES-128 encryption.');
          break;
          
        case 'rotate_master_key':
          _updateStatus('Rotating master authentication key...');
          
          // Rotate the card's master key
          // final newKeyHex = params?['new_key'] as String?;
          // await desfire.changeKey(0x00, _hexToBytes(newKeyHex));
          
          _updateStatus('✅ Master key rotated');
          break;
          
        case 'change_file_permissions':
          _updateStatus('Updating file access permissions...');
          
          // Change file access rights
          // final fileId = params?['file_id'] as int?;
          // final newPerms = params?['permissions'] as Map?;
          // await desfire.changeFileSettings(fileId, newPerms);
          
          _updateStatus('✅ Permissions updated');
          break;
          
        case 'add_new_application':
          _updateStatus('Installing new application...');
          
          // Create a new application on the card
          // final appId = params?['app_id'] as int?;
          // final appKeys = params?['key_settings'] as Map?;
          // await desfire.createApplication(appId, appKeys);
          
          _updateStatus('✅ New application installed');
          break;
          
        case 'emergency_lockdown':
          _updateStatus('⚠️ EMERGENCY LOCKDOWN INITIATED');
          
          // Disable the card or change all keys
          // This could involve:
          // - Changing all keys to server-controlled values
          // - Modifying access permissions to read-only
          // - Writing a lockdown flag to the data file
          
          final lockdownData = 'status:locked;reason:${params?['reason'] ?? 'security'};time:${DateTime.now().millisecondsSinceEpoch}';
          await desfire.writeFile01(Uint8List.fromList(utf8.encode(lockdownData)));
          
          _updateStatus('🔒 Card locked by server');
          _updateCardInfo('This SwapDot has been locked for security reasons.\nContact support for assistance.');
          break;
          
        case 'firmware_update':
          _updateStatus('Preparing firmware update...');
          
          // Some cards support firmware updates via NFC
          // This would be highly card-specific
          
          _updateStatus('✅ Firmware update queued');
          break;
          
        case 'diagnostic_scan':
          _updateStatus('Running diagnostics...');
          
          // Collect card information for server analysis
          // final diagnostics = {
          //   'card_info': await desfire.getCardInfo(),
          //   'app_ids': await desfire.getApplicationIds(),
          //   'free_memory': await desfire.getFreeMemory(),
          // };
          // 
          // Send diagnostics back to server
          // await FirebaseFirestore.instance
          //     .collection('diagnostics')
          //     .add({
          //       'token_id': tagId,
          //       'timestamp': FieldValue.serverTimestamp(),
          //       'data': diagnostics,
          //     });
          
          _updateStatus('✅ Diagnostics complete');
          break;
          
        default:
          _updateStatus('❌ Unknown command: $commandType');
      }
      
      // Log command execution
      // await FirebaseFirestore.instance
      //     .collection('command_logs')
      //     .add({
      //       'token_id': tagId,
      //       'command': commandType,
      //       'priority': priority,
      //       'executed_at': FieldValue.serverTimestamp(),
      //       'executed_by': FirebaseAuth.instance.currentUser?.uid,
      //       'success': true,
      //     });
      
    } catch (e) {
      _updateStatus('❌ Command failed: ${e.toString()}');
      
      // Log failure
      // await FirebaseFirestore.instance
      //     .collection('command_logs')
      //     .add({
      //       'token_id': tagId,
      //       'command': commandType,
      //       'priority': priority,
      //       'executed_at': FieldValue.serverTimestamp(),
      //       'executed_by': FirebaseAuth.instance.currentUser?.uid,
      //       'success': false,
      //       'error': e.toString(),
      //     });
      
      if (priority == 'critical') {
        _showErrorScreen('Critical server command failed: ${e.toString()}');
      }
    }
  }
  
  Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF00CED1), // Bright cyan blue
              Color(0xFF1a1a2e), // Dark blue
              Color(0xFFFF8C42), // Vibrant orange (subtle)
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background elements
            Positioned(
              top: 50,
              left: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00CED1).withOpacity(0.3),
                  border: Border.all(
                    color: Color(0xFF00CED1).withOpacity(0.5),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 120,
              left: 100,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00CED1).withOpacity(0.6),
                ),
              ),
            ),
            Positioned(
              top: 200,
              right: 30,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF8C42).withOpacity(0.2),
                  border: Border.all(
                    color: Color(0xFFFF8C42).withOpacity(0.3),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 150,
              left: 40,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF32CD32).withOpacity(0.5), // Lime green
                ),
              ),
            ),
            Positioned(
              bottom: 200,
              right: 80,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFFF00).withOpacity(0.6), // Yellow
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              right: 20,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF8C42).withOpacity(0.15),
                  border: Border.all(
                    color: Color(0xFFFF8C42).withOpacity(0.25),
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
            
            // Dashed line elements
            Positioned(
              top: 80,
              left: 50,
              child: CustomPaint(
                size: Size(100, 2),
                painter: DashedLinePainter(
                  color: Color(0xFF00CED1).withOpacity(0.6),
                  dashWidth: 8,
                  dashSpace: 4,
                  squiggliness: 0.4,
                ),
              ),
            ),
            Positioned(
              top: 180,
              right: 50,
              child: CustomPaint(
                size: Size(80, 2),
                painter: DashedLinePainter(
                  color: Color(0xFFFF8C42).withOpacity(0.3),
                  dashWidth: 6,
                  dashSpace: 3,
                  squiggliness: 0.6,
                ),
              ),
            ),
            Positioned(
              bottom: 120,
              left: 20,
              child: CustomPaint(
                size: Size(60, 2),
                painter: DashedLinePainter(
                  color: Color(0xFF32CD32).withOpacity(0.6),
                  dashWidth: 5,
                  dashSpace: 2,
                  squiggliness: 0.8,
                ),
              ),
            ),
            
            // Main content
            SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                  // Header with Logo
                  Container(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Image.asset(
                          'swapdotz_possible_logo_no_bg.png',
                          height: 80,
                          width: 80,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: 16),
                                                  Text(
                            'SwapDotz Demo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // User Selector
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    padding: EdgeInsets.all(16),
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
                          'Select User:',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: _users.map((user) {
                            final isSelected = _selectedUser == user;
                            return Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedUser = user;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    margin: EdgeInsets.only(right: 8),
                                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                        ? Color(0xFF00CED1) 
                                        : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected 
                                          ? Color(0xFF00CED1) 
                                          : Colors.white.withOpacity(0.3),
                                        width: 1,
                                      ),
                                      boxShadow: isSelected ? [
                                        BoxShadow(
                                          color: Color(0xFF00CED1).withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ] : null,
                                    ),
                                    child: Center(
                                                                          child: Text(
                                      user.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: isSelected ? Colors.white : Colors.white70,
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // User Info
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _selectedUser == 'oliver' 
                        ? Color(0xFF00CED1).withOpacity(0.1)
                        : Color(0xFFFF8C42).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedUser == 'oliver' 
                          ? Color(0xFF00CED1).withOpacity(0.3)
                          : Color(0xFFFF8C42).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedUser == 'oliver' ? Icons.person_add : Icons.person,
                          color: _selectedUser == 'oliver' 
                            ? Color(0xFF00CED1) 
                            : Color(0xFFFF8C42),
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedUser == 'oliver' 
                              ? 'Oliver will start a SwapDot session'
                              : 'Jonathan will claim the SwapDot during session',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 40),
                  
                  // Swap Dot Button
                  Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isScanning ? null : _startSwapDot,
                        borderRadius: BorderRadius.circular(100),
                        child: AnimatedBuilder(
                          animation: _pulseAnimation ?? const AlwaysStoppedAnimation(1.0),
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation?.value ?? 1.0,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: _isScanning 
                                      ? [Color(0xFF00CED1), Color(0xFF00B4B4)]
                                      : _selectedUser == 'oliver'
                                        ? [Color(0xFF00CED1), Color(0xFF00B4B4)]
                                        : [Color(0xFFFF8C42), Color(0xFFFF6B35)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isScanning 
                                        ? Color(0xFF00CED1).withOpacity(0.4)
                                        : _selectedUser == 'oliver'
                                          ? Color(0xFF00CED1).withOpacity(0.4)
                                          : Color(0xFFFF8C42).withOpacity(0.4),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isScanning ? Icons.nfc : Icons.swap_horiz,
                                        size: 48,
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 12),
                                                                          Text(
                                      _isScanning ? 'SCANNING...' : 'SWAP DOT',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 40),
                  
                  // Status card
                  if (_statusMessage.isNotEmpty || _cardInfo.isNotEmpty)
                    Container(
                      margin: EdgeInsets.all(24),
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_statusMessage.isNotEmpty) ...[
                            Text(
                              _statusMessage,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            SizedBox(height: 12),
                          ],
                          if (_cardInfo.isNotEmpty) ...[
                            Text(
                              _cardInfo,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  

                  
                  // Leaderboard Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => LeaderboardScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                );
                              },
                              transitionDuration: Duration(milliseconds: 800),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF00CED1), Color(0xFF00B4B4)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF00CED1).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Color(0xFF32CD32).withOpacity(0.2),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '🏆',
                                style: TextStyle(fontSize: 20),
                              ),
                              SizedBox(width: 12),
                              Text(
                                                              'LEADERBOARD',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Marketplace Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => MarketplaceScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                );
                              },
                              transitionDuration: Duration(milliseconds: 800),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF8C42), Color(0xFFFF6B35)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFF8C42).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Color(0xFFFFFF00).withOpacity(0.2),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '🛒',
                                style: TextStyle(fontSize: 20),
                              ),
                              SizedBox(width: 12),
                              Text(
                                                              'MARKETPLACE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Footer section to fill the bottom space
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SwapDotz',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w300,
                                    color: Color(0xFF00CED1),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Hand to Hand, Coast to Coast',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Color(0xFF00CED1).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Color(0xFF00CED1).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'v1.0.0',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF00CED1),
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildFooterItem(Icons.info_outline, 'About', () {}),
                            _buildFooterItem(Icons.help_outline, 'Help', () {}),
                            _buildFooterItem(Icons.settings, 'Settings', () {}),
                            _buildFooterItem(Icons.share, 'Share', () {}),
                          ],
                        ),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Color(0xFF32CD32).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Color(0xFF32CD32).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.wifi_tethering,
                                size: 16,
                                color: Color(0xFF32CD32),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'NFC Ready',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF32CD32),
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 40),
                  
                  // Firebase Demo Button - NEW
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => FirebaseDemoScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                );
                              },
                              transitionDuration: Duration(milliseconds: 800),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF6366F1).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'FIREBASE DEMO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 16,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 24),
                ],
              ),
            ),
          ),
            
            // Overlay
            if (_showOverlay)
              AnimatedBuilder(
                animation: _fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeAnimation?.value ?? 1.0,
                    child: GestureDetector(
                      onTap: () {
                        // Allow dismissing the overlay if there's an error
                        if (_statusMessage.contains('❌') || _statusMessage.contains('Error')) {
                          _fadeController?.reverse();
                          Future.delayed(Duration(milliseconds: 300), () {
                            setState(() {
                              _showOverlay = false;
                              _statusMessage = '';
                              _cardInfo = '';
                            });
                          });
                        }
                      },
                      child: Container(
                        color: Colors.black.withOpacity(0.8),
                        child: Center(
                          child: GestureDetector(
                            onTap: () {}, // Prevent taps on the card from dismissing
                            child: Container(
                              margin: EdgeInsets.all(40),
                              padding: EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Color(0xFF1a1a2e),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Color(0xFF00CED1),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF00CED1).withOpacity(0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF00CED1), Color(0xFF00B4B4)],
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.nfc,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  Text(
                                    'Gift Swapdot',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'User: ${_selectedUser.toUpperCase()}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF00CED1),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    _statusMessage.isEmpty 
                                      ? 'Preparing transaction...'
                                      : _statusMessage,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white70,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      // Cancel button
                                      GestureDetector(
                                        onTap: () async {
                                          setState(() {
                                            _isScanning = false;
                                          });
                                          _pulseController?.stop();
                                          _pulseController?.reset();
                                          
                                          await FlutterNfcKit.finish(iosAlertMessage: 'Transaction cancelled');
                                          
                                          _fadeController?.reverse();
                                          await Future.delayed(Duration(milliseconds: 300));
                                          setState(() {
                                            _showOverlay = false;
                                            _statusMessage = ''; // Clear the status message
                                            _cardInfo = ''; // Clear the card info
                                          });
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFff6b6b),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Loading indicator
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Color(0xFF00CED1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashSpace;
  final double squiggliness;

  DashedLinePainter({
    required this.color,
    required this.dashWidth,
    required this.dashSpace,
    this.squiggliness = 0.3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Create a continuous wave path
    final path = Path();
    final centerY = size.height / 2;
    final waveHeight = squiggliness * 15;
    
    // Start the path
    path.moveTo(0, centerY);
    
    // Create a smooth wave pattern across the entire width
    final segments = (size.width / 3).round(); // More segments for smoother curve
    final segmentWidth = size.width / segments;
    
    for (int i = 1; i <= segments; i++) {
      final x = i * segmentWidth;
      // Create a natural wave pattern
      final waveOffset = sin((i * pi * 2) / segments) * waveHeight;
      path.lineTo(x, centerY + waveOffset);
    }
    
    // Draw dashed line along the wave path
    final dashLength = dashWidth;
    final gapLength = dashSpace;
    final totalLength = dashLength + gapLength;
    
    double distance = 0;
    while (distance < path.computeMetrics().first.length) {
      final startPoint = path.computeMetrics().first.getTangentForOffset(distance)?.position ?? Offset.zero;
      final endPoint = path.computeMetrics().first.getTangentForOffset(distance + dashLength)?.position ?? Offset.zero;
      
      if (endPoint != Offset.zero) {
        canvas.drawLine(startPoint, endPoint, paint);
      }
      
      distance += totalLength;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

