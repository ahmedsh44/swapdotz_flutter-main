import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/firebase_service.dart';

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with TickerProviderStateMixin {
  Future<void>? _initFuture;
  late AnimationController _logoController;
  late AnimationController _textController;
  late Animation<double> _logoAnimation;
  late Animation<double> _textAnimation;
  late Animation<double> _logoRotationAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize splash screen animations
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
    
    _initFuture = _initialize();
    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(Duration(milliseconds: 200));
    if (mounted) _logoController.forward();
    
    await Future.delayed(Duration(milliseconds: 600));
    if (mounted) _textController.forward();
  }

  Future<void> _initialize() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    // Ensure anonymous authentication before showing UI
    final user = await SwapDotzFirebaseService.authenticateAnonymously();
    if (user != null) {
      print('✅ User authenticated during app init: ${user.uid}');
    } else {
      print('❌ Failed to authenticate user during app init');
    }
    
    // Test Firestore connection
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('config').doc('app').get();

    // Ensure splash screen shows for at least 2.5 seconds total
    await Future.delayed(Duration(milliseconds: 2500));
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Widget _buildSplashScreen() {
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
                          angle: -_logoRotationAnimation.value * 2 * math.pi,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: snapshot.connectionState == ConnectionState.waiting
              ? _buildSplashScreen()
              : SwapDotzApp(),
        );
      },
    );
  }
} 