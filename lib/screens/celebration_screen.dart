import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/firebase_service.dart';
import 'package:audioplayers/audioplayers.dart';

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

  String? _rarity; // common | uncommon | rare
  late final AnimationController _confettiController;
  late final AnimationController _burstController;
  late final AnimationController _shockwaveController;
  final AudioPlayer _audioPlayer = AudioPlayer();

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

    _confettiController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _burstController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );

    _shockwaveController = AnimationController(
      duration: Duration(milliseconds: 2000), // Longer for more impact
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
    _loadRarity();
  }

  Future<void> _loadRarity() async {
    // Lazy-fetch token to determine rarity for visuals
    final token = await SwapDotzFirebaseService.getToken(widget.swapDotId);
    setState(() {
      _rarity = token?.metadata.rarity?.toLowerCase() ?? 'common';
    });
  }

  /// Play sound effect based on token rarity
  Future<void> _playRaritySound(String rarity) async {
    try {
      await _audioPlayer.play(AssetSource('SwapSounds/$rarity.mp3'));
      print('🔊 Playing $rarity celebration sound effect');
    } catch (e) {
      print('🔊 Failed to play $rarity sound: $e');
    }
  }

  void _startAnimations() async {
    // Start with splash animation
    _splashController.forward();
    
    // Don't auto-transition - wait for user to tap X
    // The transition will be handled by the X button tap
  }

  void _startMainCelebrationAnimations() async {
    // Start rarity-specific bursts
    _playRarityCelebration();

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

  void _playRarityCelebration() {
    final rarity = _rarity ?? 'common';
    
    // Play appropriate sound effect
    _playRaritySound(rarity);
    
    switch (rarity) {
      case 'rare':
        // 🌟 RARE SWAPDOT celebration for rare tokens!
        _confettiController.forward(from: 0);
        _burstController.forward(from: 0);
        _shockwaveController.forward(from: 0);
        break;
      case 'uncommon':
        // 💫 UNCOMMON SWAPDOT celebration!
        _confettiController.forward(from: 0);
        _burstController.forward(from: 0);
        break;
      default: // common
        // ✨ COMMON SWAPDOT celebration
        _confettiController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _mapController.dispose();
    _celebrityController.dispose();
    _splashController.dispose();
    _confettiController.dispose();
    _burstController.dispose();
    _shockwaveController.dispose();
    _audioPlayer.dispose();
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

  String _getRarityTitleText() {
    final rarity = _rarity ?? 'common';
    switch (rarity) {
      case 'rare':
        return 'RARE SWAPDOT!';
      case 'uncommon':
        return 'UNCOMMON SWAPDOT!';
      default: // common
        return 'COMMON SWAPDOT!';
    }
  }

  Color _getRarityTitleColor() {
    final rarity = _rarity ?? 'common';
    switch (rarity) {
      case 'rare':
        return Color(0xFFFFD700); // Gold
      case 'uncommon':
        return Color(0xFF00CED1); // Cyan
      default: // common
        return Color(0xFF32CD32); // Green
    }
  }

  List<Color> _getRarityGradientColors() {
    final rarity = _rarity ?? 'common';
    switch (rarity) {
      case 'rare':
        return [
          Color(0xFFFF6B35), // Vibrant orange
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFFFFD700), // Gold
        ];
      case 'uncommon':
        return [
          Color(0xFF4A90E2), // Bright blue
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFF00CED1), // Cyan
        ];
      default: // common
        return [
          Color(0xFF32CD32), // Green
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFF90EE90), // Light green
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _getRarityGradientColors(),
          ),
        ),
        child: Stack(
          children: [
            
            // Rarity overlays
            if ((_rarity ?? 'common') == 'common') _buildCommonConfetti(),
            if ((_rarity ?? 'common') == 'uncommon') ...[
              _buildCommonConfetti(),
              _buildBurstRays(intensity: 0.8, rayCount: 32), // More intense for uncommon
            ],
            if ((_rarity ?? 'common') == 'rare') ...[
              _buildCommonConfetti(),
              _buildBurstRays(intensity: 1.5, rayCount: 48), // INTENSE for rare
              _buildShockwave(),
              _buildGlobalGlow(),
              _buildScreenShake(), // Extra earthshattering effect!
            ],
            
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
                  _getRarityTitleText(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getRarityTitleColor(),
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

  Widget _buildCommonConfetti() {
    final rarity = _rarity ?? 'common';
    int confettiCount;
    switch (rarity) {
      case 'rare':
        confettiCount = 100; // Reduced but still dramatic
        break;
      case 'uncommon':
        confettiCount = 60; // Reduced for performance  
        break;
      default:
        confettiCount = 30; // Reduced for performance
    }
    
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _confettiController,
        builder: (context, _) {
          final t = _confettiController.value;
          return CustomPaint(
            painter: _ConfettiPainter(progress: t, count: confettiCount),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildBurstRays({double intensity = 1.0, int rayCount = 24}) {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _burstController,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_burstController.value);
          return CustomPaint(
            painter: _BurstPainter(progress: t, rayCount: rayCount, color: Colors.amberAccent.withOpacity(0.9)),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildScreenShake() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _shockwaveController,
        builder: (context, _) {
          final t = _shockwaveController.value;
          // Create subtle screen shake effect for rare tokens
          final shakeOffset = math.sin(t * 20) * (1 - t) * 3;
          return Transform.translate(
            offset: Offset(shakeOffset, 0),
            child: Container(), // Empty container just for the shake effect
          );
        },
      ),
    );
  }

  Widget _buildShockwave() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _shockwaveController,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_shockwaveController.value);
          return CustomPaint(
            painter: _ShockwavePainter(progress: t, color: Colors.amberAccent.withOpacity(0.7)),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildGlobalGlow() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _burstController,
        builder: (context, _) {
          final opacity = (1 - _burstController.value).clamp(0.0, 1.0);
          return Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.12 * opacity),
                  blurRadius: 80,
                  spreadRadius: 40,
                ),
              ],
            ),
          );
        },
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

class _ConfettiPainter extends CustomPainter {
  final double progress; // 0..1
  final int count;
  _ConfettiPainter({required this.progress, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    for (int i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final radius = progress * (size.shortestSide * 0.6) * rnd.nextDouble();
      final cx = size.width / 2 + math.cos(angle) * radius;
      final cy = size.height / 3 + math.sin(angle) * radius;
      final paint = Paint()
        ..color = Color.lerp(Colors.cyanAccent, Colors.orangeAccent, rnd.nextDouble())!.withOpacity(1 - progress)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), 2 + rnd.nextDouble() * 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}

class _BurstPainter extends CustomPainter {
  final double progress; // 0..1
  final int rayCount;
  final Color color;
  _BurstPainter({required this.progress, required this.rayCount, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 3);
    final paint = Paint()
      ..color = color.withOpacity((1 - progress) * 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < rayCount; i++) {
      final angle = (2 * math.pi / rayCount) * i;
      final length = size.shortestSide * 0.15 * Curves.easeOut.transform(progress);
      final dx = math.cos(angle) * length;
      final dy = math.sin(angle) * length;
      canvas.drawLine(center, center.translate(dx, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.rayCount != rayCount;
}

class _ShockwavePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  _ShockwavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 3);
    final radius = size.shortestSide * 0.1 + progress * size.shortestSide * 0.4;
    final paint = Paint()
      ..color = color.withOpacity((1 - progress) * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * (1 - progress);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _ShockwavePainter oldDelegate) => oldDelegate.progress != progress;
}

 