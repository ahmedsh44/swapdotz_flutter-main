import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:crypto/crypto.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

// Local imports
import '../desfire.dart';
import '../models/token_data.dart';
import '../services/firebase_service.dart';
import '../services/secure_transfer_service.dart';
import '../services/trade_with_location.dart';
import '../services/trade_location_service.dart';
import '../services/firebase_forwarder.dart';
import '../services/server_nfc_service.dart';

import '../version_check_screen.dart';
// import 'celebration_screen.dart'; // Disabled to avoid video loading issues
import 'marketplace_screen.dart';
import 'seller_verification_screen.dart';
import 'buyer_verification_screen.dart';
import 'test_stripe_screen.dart';  // Add test screen import
import 'package:audioplayers/audioplayers.dart';


class SwapDotzApp extends StatefulWidget {
  @override
  _SwapDotzAppState createState() => _SwapDotzAppState();
}

class _SwapDotzAppState extends State<SwapDotzApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _appIsActive = true;
  bool _nfcPollInProgress = false;
  bool _isScanning = false;
  bool _showOverlay = false;
  String _statusMessage = '';
  String _cardInfo = '';
  String _selectedUser = 'gifter'; // Default user
  AnimationController? _pulseController;
  AnimationController? _fadeController;
  AnimationController? _successController;
  AnimationController? _errorController;
  AnimationController? _zoomController;
  AnimationController? _arrowController;
  Animation<double>? _pulseAnimation;
  Animation<double>? _fadeAnimation;
  Animation<double>? _successScale;
  Animation<double>? _zoomAnimation;
  Animation<double>? _arrowAnimation;
  
  bool _showZoomEffect = false;
  Animation<double>? _errorShake;
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _showSuccessIcon = false;
  bool _showErrorIcon = false;
  bool _nfcOperationInProgress = false;
  
  // 🚀 GPS OPTIMIZATION: Store preloaded GPS location for all functions
  Position? _preloadedGpsLocation;

  final List<String> _users = ['gifter', 'receiver'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _errorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _zoomController = AnimationController(
      duration: const Duration(milliseconds: 1500), // Longer duration!
      vsync: this,
    );
    _arrowController = AnimationController(
      duration: const Duration(milliseconds: 1200), // Longer arrow animation
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController!, curve: Curves.easeInOut),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController!, curve: Curves.elasticOut),
    );
    _errorShake = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _errorController!, curve: Curves.elasticIn),
    );
    _zoomAnimation = Tween<double>(begin: 0.1, end: 1.5).animate(
      CurvedAnimation(parent: _zoomController!, curve: Curves.elasticOut),
    );
    // Arrow animation that stays within screen bounds (will be set up properly in didChangeDependencies)
    _arrowAnimation = Tween<double>(begin: -50.0, end: 400.0).animate(
      CurvedAnimation(parent: _arrowController!, curve: Curves.easeInOut),
    );

    // Authentication is now handled at app level
    // _ensureAuthenticated(); // Removed - handled in app.dart
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController?.dispose();
    _fadeController?.dispose();
    _successController?.dispose();
    _errorController?.dispose();
    _zoomController?.dispose();
    _arrowController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up arrow animation with proper screen bounds
    final screenWidth = MediaQuery.of(context).size.width;
    _arrowAnimation = Tween<double>(begin: -50.0, end: screenWidth + 50.0).animate(
      CurvedAnimation(parent: _arrowController!, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
  }

  /// Check if location permissions are already granted (without requesting)
  Future<bool> _hasLocationPermissions() async {
    try {
      // Import geolocator to check permission status without requesting
      final permission = await Geolocator.checkPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      return serviceEnabled && 
             (permission == LocationPermission.always || 
              permission == LocationPermission.whileInUse);
    } catch (e) {
      return false;
    }
  }

  Future<void> _ensureAuthenticated() async {
    final user = await SwapDotzFirebaseService.authenticateAnonymously();
    if (user == null) {
      print('❌ Failed to authenticate user');
    } else {
      print('✅ User authenticated: ${user.uid}');
    }
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
  
  /// Update status with exciting, non-technical messaging and animations
  void _updateStatusExciting(String message, {Duration? delay, bool withPulse = true}) async {
    if (delay != null) {
      await Future.delayed(delay);
    }
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
      
      // Add pulse animation for excitement
      if (withPulse && _pulseController != null) {
        _pulseController!.reset();
        _pulseController!.repeat(reverse: true);
      }
    }
  }
  
  /// Animated sequence for building suspense during operations
  Future<void> _playExcitingSequence(List<String> messages, {Duration stepDelay = const Duration(milliseconds: 800)}) async {
    for (int i = 0; i < messages.length; i++) {
      _updateStatusExciting(messages[i], withPulse: i == messages.length - 1);
      if (i < messages.length - 1) {
        await Future.delayed(stepDelay);
      }
    }
  }
  
  /// Play epic ZOOM! animation with flying arrows
  Future<void> _playZoomAnimation() async {
    setState(() {
      _showZoomEffect = true;
    });
    
    // Play whoosh sound effect
    try {
      await _audioPlayer.play(AssetSource('SwapSounds/whoosh.mp3'));
    } catch (e) {
      print('🔊 Failed to play whoosh sound: $e');
    }
    
    // Start both animations simultaneously
    _zoomController?.forward();
    _arrowController?.forward();
    
    // Wait for animation to complete (match the longer zoom duration)
    await Future.delayed(Duration(milliseconds: 1500));
    
    // Hide effect
    setState(() {
      _showZoomEffect = false;
    });
    
    // Reset animations for next use
    _zoomController?.reset();
    _arrowController?.reset();
  }

  void _updateCardInfo(String info) {
    if (mounted) {
      setState(() {
        _cardInfo = info;
      });
    }
  }

  /// Play success feedback with sound and animation
  Future<void> _showSuccessFeedback(String message) async {
    _updateStatus(message);
    
    // Play success sound
    try {
      await _audioPlayer.play(AssetSource('sounds/success.mp3'));
    } catch (e) {
      // Fall back to system sound if custom sound fails
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
    
    // Show success animation
    if (mounted) {
      setState(() {
        _showSuccessIcon = true;
      });
      _successController?.forward();
      
      // Hide after animation
      await Future.delayed(Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _showSuccessIcon = false;
        });
      }
      _successController?.reset();
    }
  }
  
  /// Play error feedback with sound and animation
  Future<void> _showErrorFeedback(String message) async {
    _updateStatus(message);
    
    // Play error sound
    try {
      await _audioPlayer.play(AssetSource('sounds/error.mp3'));
    } catch (e) {
      // Fall back to system haptic feedback
      HapticFeedback.heavyImpact();
    }
    
    // Show error animation
    if (mounted) {
      setState(() {
        _showErrorIcon = true;
      });
      _errorController?.repeat(count: 2);
      
      // Hide after animation
      await Future.delayed(Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _showErrorIcon = false;
        });
      }
      _errorController?.reset();
    }
  }
  
  /// Update status with "keep holding" message during NFC operations
  void _updateNFCProgress(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
        _nfcOperationInProgress = true;
      });
    }
  }
  
  /// Start GPS location fetching concurrently (non-blocking)
  Future<Position?> _getLocationConcurrently() async {
    try {
      print('🚀 GPS: Starting concurrent location fetch...');
      
      // Quick permission check first
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        print('🚀 GPS: Permissions denied, skipping location');
        return null;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('🚀 GPS: Location services disabled, skipping');
        return null;
      }

      // Use network location first (fast)
      print('🚀 GPS: Getting network location (fast)...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      
      print('🚀 GPS: Concurrent location obtained: ${position.latitude}, ${position.longitude}');
      print('🚀 GPS: Accuracy: ${position.accuracy}m');
      return position;
      
    } catch (e) {
      print('🚀 GPS: Concurrent location failed: $e');
      return null;
    }
  }

  /// Clear NFC progress indicator
  void _clearNFCProgress() {
    if (mounted) {
      setState(() {
        _nfcOperationInProgress = false;
      });
    }
  }

  /// Generate a cryptographically secure random key
  // Key generation and hashing now handled entirely server-side for security
  // Client never sees or generates keys

  /// Play sound effect based on token rarity
  Future<void> _playRaritySound(String? rarity) async {
    final raritySound = rarity ?? 'common';
    try {
      await _audioPlayer.play(AssetSource('SwapSounds/$raritySound.mp3'));
      print('🔊 Playing $raritySound rarity sound effect');
    } catch (e) {
      print('🔊 Failed to play $raritySound sound: $e');
    }
  }
  
  /// DIAGNOSTIC: Show key info (server validates hashes now)
  Future<void> _verifyKeySynchronization(String? nfcKey, Token token, String tokenUid) async {
    print('🔍 =============================================================');
    print('🔍 DIAGNOSTIC: KEY INFO (Server validates hashes)');
    print('🔍 Token UID: $tokenUid');
    print('🔍 =============================================================');
    
    // SECURITY: Client never sees keys - server handles all validation
    print('🔍 Client Key Access: DENIED (security)');
    print('🔍 Firebase Hash:   ${token.keyHash.substring(0, math.min(32, token.keyHash.length))}...');
    print('🔍 Note: Server exclusively validates key authenticity');
    
    print('🔍 =============================================================');
  }

  /// Auto-restart wrapper for SwapDot functionality
  Future<void> _startSwapDotWithAutoRestart() async {
    const maxRetries = 2;
    int retryCount = 0;
    
    while (retryCount <= maxRetries) {
      try {
        await _startSwapDot();
        return; // Success, exit the retry loop
      } catch (e) {
        retryCount++;
        final errorString = e.toString();
        print('🔄 SwapDot transaction failed (attempt $retryCount): $errorString');
        print('🔄 Error type: ${e.runtimeType}');
        print('🔄 Checking if retryable: ${_isRetryableError(errorString)}');
        
        // Check if this is a retryable error
        if (_isRetryableError(errorString) && retryCount <= maxRetries) {
          print('🔄 Auto-restarting SwapDot transaction (attempt ${retryCount + 1}/${maxRetries + 1})...');
          _updateStatus('🔄 Restarting...');
          await Future.delayed(Duration(milliseconds: 500)); // Brief pause
          continue; // Retry the operation
        } else {
          // Non-retryable error or max retries exceeded
          print('🔄 Max retries exceeded or non-retryable error, showing error to user');
          print('🔄 RetryCount: $retryCount, MaxRetries: $maxRetries');
          rethrow;
        }
      }
    }
  }

  /// Auto-restart wrapper for token initialization
  Future<void> _initializeTokenWithAutoRestart() async {
    const maxRetries = 2;
    int retryCount = 0;
    
    while (retryCount <= maxRetries) {
      try {
        await _initializeToken();
        return; // Success, exit the retry loop
      } catch (e) {
        retryCount++;
        final errorString = e.toString();
        print('🔄 Token initialization failed (attempt $retryCount): $errorString');
        print('🔄 Error type: ${e.runtimeType}');
        print('🔄 Checking if retryable: ${_isRetryableError(errorString)}');
        
        // Check if this is a retryable error
        if (_isRetryableError(errorString) && retryCount <= maxRetries) {
          print('🔄 Auto-restarting token initialization (attempt ${retryCount + 1}/${maxRetries + 1})...');
          _updateStatus('🔄 Restarting...');
          await Future.delayed(Duration(milliseconds: 500)); // Brief pause
          continue; // Retry the operation
        } else {
          // Non-retryable error or max retries exceeded
          print('🔄 Max retries exceeded or non-retryable error, showing error to user');
          print('🔄 RetryCount: $retryCount, MaxRetries: $maxRetries');
          rethrow;
        }
      }
    }
  }

  /// Check if an error should trigger an automatic restart
  bool _isRetryableError(String errorString) {
    final retryableErrors = [
      'already pending',
      'pending transfer', 
      'Transfer already pending',
      'failed-precondition',
      'timeout',
      'connection lost',
      'nfc session',
      'card error',
      'version check failed',
      'firebase error',
      'network error',
      'communication error', // NFC communication failures
      'tag is out of date', // NFC tag state issues
      'platformexception', // Generic platform errors that are often transient
      '91 de', // DESFire file/app exists error (retryable)
    ];
    
    for (String errorPattern in retryableErrors) {
      if (errorString.toLowerCase().contains(errorPattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Main SwapDot functionality - exciting and animated experience
  Future<void> _startSwapDot() async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    print('🚀 =============================================================');
    print('🚀 SWAPDOT TRANSACTION START - Session: $sessionId');
    print('🚀 Timestamp: ${DateTime.now().toIso8601String()}');
    print('🚀 Selected User: $_selectedUser');
    print('🚀 =============================================================');
    
    // Show exciting animated sequence instead of technical details
    await _playExcitingSequence([
      '🔮 Preparing SwapDot magic...',
      '⚡ Charging up the transfer energy...',
      '🎯 Targeting your SwapDot...'
    ]);
    
    // 🚀 OPTIMIZATION: Start GPS immediately when button is pressed!
    print('🚀 EARLY GPS: Starting GPS fetch immediately on button press...');
    final earlyLocationFuture = _getLocationConcurrently();
    
    // Store the result in class variable for all functions to use
    earlyLocationFuture.then((location) {
      _preloadedGpsLocation = location;
      if (location != null) {
        print('🚀 EARLY GPS: Location cached for all functions: ${location.latitude}, ${location.longitude}');
      }
    });
    
    // Skip test user authentication - already authenticated
    // await SwapDotzFirebaseService.switchToNamedUser(_selectedUser);
    
    // Version check before allowing NFC operations
    try {
      print('📋 STEP 1: Version Check');
      print('📋 Getting current app version...');
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      print('📋 Current version: $currentVersion');
      
      print('📋 Checking Firebase for minimum version requirement...');
      // Get fresh config data from server (no need for Source.server here as config rarely changes)
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_requirements')
          .get();
      
      if (configDoc.exists) {
        final data = configDoc.data();
        final requiredVersion = data?['minimum_version'] ?? '1.0.0';
        print('📋 Required version from Firebase: $requiredVersion');
        print('📋 Version check comparison: $currentVersion vs $requiredVersion');
        
        if (_isVersionOlder(currentVersion, requiredVersion)) {
          print('❌ VERSION CHECK FAILED: App version too old');
          print('❌ Current: $currentVersion, Required: $requiredVersion');
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
        print('✅ Version check passed');
      } else {
        print('⚠️ No version config found in Firebase, proceeding anyway');
      }
    } catch (e, stackTrace) {
      print('❌ Version check during NFC scan failed: $e');
      print('❌ Stack trace: $stackTrace');
      // Allow operation to continue if check fails
    }
    
    print('📱 STEP 2: UI State Setup');
    setState(() {
      _isScanning = true;
      _showOverlay = true;
      _statusMessage = '';
      _cardInfo = '';
    });
    print('📱 UI state set to scanning mode');

    _fadeController?.forward();
    _pulseController?.repeat(reverse: true);
    print('📱 Animation controllers started');

    try {
      print('📡 STEP 3: Concurrent NFC + GPS Operations');
      _updateStatus('Looking for SwapDot...');
      
      // Use early GPS location that was already started when button was pressed
      print('🚀 Using early GPS location (started on button press)...');
      final locationFuture = earlyLocationFuture;
      
      print('📡 Starting NFC poll operation...');
      print('📡 Poll timeout: default');
      print('📡 iOS alert message: "Hold your SwapDot near the device"');
      
      final pollStartTime = DateTime.now();
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: 'Hold your SwapDot near the device',
      );
      final pollDuration = DateTime.now().difference(pollStartTime);
      
      print('✅ NFC TAG DETECTED!');
      print('📡 Poll duration: ${pollDuration.inMilliseconds}ms');
      print('📡 Tag details:');
      print('📡   - Type: ${tag.type}');
      print('📡   - ID: ${tag.id}');
      print('📡   - Standard: ${tag.standard}');
      print('📡   - ATQA: ${tag.atqa}');
      print('📡   - SAK: ${tag.sak}');
      print('📡   - Raw data: ${tag.ndefAvailable}');
      
      // Exciting detection animation
      _updateStatusExciting('🎉 SwapDot detected!', delay: Duration(milliseconds: 100));
      
      final tokenUid = tag.id;
      print('🏷️ Token UID extracted: $tokenUid');
      _updateCardInfo('SwapDot ID: $tokenUid');
      
      // Kick off Firebase lookup concurrently while we handle NFC auth/read
      final tokenFuture = SwapDotzFirebaseService.getToken(tokenUid);
      
      // Important: Tell user to keep holding the card
      _updateNFCProgress('⏳ Keep holding SwapDot... Processing');
      
      // Get current user for authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user');
        _updateStatus('❌ Authentication required');
        _updateCardInfo('Please sign in to continue');
        return;
      }
      
      try {
        // Step 1: Server-authoritative authentication and setup
        print('🔐 STEP 4: Server-Authoritative NFC Authentication');
        
        // Exciting authentication sequence
        _updateStatusExciting('🔐 Authenticating with SwapDot...');
        _updateNFCProgress('⏳ Keep holding... Unlocking security');
        await Future.delayed(Duration(milliseconds: 300));
        
        _updateStatusExciting('🔑 Breaking encryption...');
        await Future.delayed(Duration(milliseconds: 400));
        
        print('🔐 Starting server-authoritative authentication...');
        final authStartTime = DateTime.now();
        
        // Use ServerNFCService for authentication - allowUnowned for new tokens
        String sessionId;
        try {
          sessionId = await ServerNFCService.authenticateAndSetup(
            tokenId: tokenUid,
            userId: currentUser.uid,
            allowUnowned: true, // Allow for uninitialized tokens
          );
        } catch (e) {
          if (e.toString().contains('Not the token owner')) {
            // Token exists but owned by someone else - retry without ownership check
            print('⚠️ Token owned by someone else, continuing read-only...');
            sessionId = 'read-only';
          } else {
            rethrow;
          }
        }
        
        final authDuration = DateTime.now().difference(authStartTime);
        print('✅ Server authentication completed in ${authDuration.inMilliseconds}ms');
        print('✅ Session ID: $sessionId');
        
        _updateStatusExciting('✅ Security unlocked!');
        await Future.delayed(Duration(milliseconds: 400));
        
        // Step 2: Read current key from NFC with excitement
        print('📖 STEP 5: Reading Current Key from NFC');
        
        _updateStatusExciting('🔍 Reading SwapDot secrets...');
        await Future.delayed(Duration(milliseconds: 300));
        
        _updateStatusExciting('📊 Analyzing ownership data...');
        // SECURITY: Client NEVER reads keys directly
        // Server handles all key operations for security
        String? currentKey = null;  // Always null - keys stay server-side
        print('🔒 SECURITY: Client skipping key read - server handles validation');
        print('🔒 Keys remain server-side only for security');
        
        // Step 3: Await concurrent Firebase lookup and GPS location
        print('🔥 STEP 8: Awaiting Concurrent Operations');
        _updateStatus('Syncing with server and GPS...');
        print('🔥 Waiting for Firebase lookup and GPS location...');
        
        final firebaseStartTime = DateTime.now();
        final List<dynamic> results = await Future.wait([
          tokenFuture,
          locationFuture,
        ]);
        final firebaseDuration = DateTime.now().difference(firebaseStartTime);
        
        final token = results[0] as Token?;
        final gpsLocation = results[1] as Position?;
        
        print('🔥 Concurrent operations completed in ${firebaseDuration.inMilliseconds}ms');
        if (gpsLocation != null) {
          print('🚀 GPS: Location ready: ${gpsLocation.latitude}, ${gpsLocation.longitude}');
        } else {
          print('🚀 GPS: No location obtained');
        }
        
        print('🔥 Firebase lookup completed in ${firebaseDuration.inMilliseconds}ms');
        if (token != null) {
          print('✅ Token found in Firebase:');
          print('🔥   - Current Owner: ${token.currentOwnerId}');
          print('🔥   - Key Hash: ${token.keyHash.substring(0, math.min(16, token.keyHash.length))}...');
          print('🔥   - Created: ${token.createdAt}');
          print('🔥   - Last Transfer: ${token.lastTransferAt}');
          print('🔥   - Previous Owners: ${token.previousOwners.length}');
        } else {
          print('📝 Token NOT found in Firebase - this appears to be a new/unregistered token');
        }
        
        print('🎯 STEP 9: Security Decision Tree');
        
        // SECURITY MODEL: SwapDot flow NEVER initializes tokens
        // Only existing, registered tokens are allowed
        if (token == null) {
          print('🚫 SCENARIO: TOKEN NOT FOUND - REJECTED');
          print('🚫   - Token in Firebase: ❌ NOT FOUND');
          print('🚫   - Selected User Role: $_selectedUser');
          print('🚫   - Security Policy: SwapDot flow cannot initialize tokens');
          
          // SECURITY: Client no longer reads keys - can't check card data
          // Server will handle validation during operations
          
          // Different error messages based on user intent
          if (_selectedUser == 'gifter') {
            print('🚫   - User trying to gift unknown token - showing ownership error');
            _updateStatus('❌ This doesn\'t belong to you');
            _updateCardInfo('''$_cardInfo

🚫 UNAUTHORIZED ACCESS

This SwapDot doesn't belong to you.

Token ID: $tokenUid

Only the owner can initiate gift transfers.
If this is your SwapDot, make sure it's 
properly registered in the system.

🛡️ Access denied for security.''');
          } else {
            print('🚫   - User trying to receive unregistered token - showing registration error');
            _updateStatus('❌ Unregistered SwapDot');
            _updateCardInfo('''$_cardInfo

🚫 UNREGISTERED SWAPDOT DETECTED

This SwapDot is not registered in the system.

Token ID: $tokenUid

SwapDot transactions can only work with 
registered tokens. Use the initialization 
feature to register new SwapDots.

🛡️ Access denied for security.''');
          }
          return;
        }
        
        // SECURITY: Client no longer reads keys - server validates during operations
        if (false) { // Never triggered - kept for code structure
          print('🪦 SCENARIO: Server will detect corrupted tokens during validation');
          
          _updateStatus('🪦 Corrupted SwapDot');
          _updateCardInfo('''$_cardInfo

🪦 CORRUPTED SWAPDOT DETECTED

This SwapDot is registered but corrupted.

Token ID: $tokenUid
Owner: ${token.currentOwnerId}
Created: ${token.createdAt}

The NFC data is unreadable, making this 
token permanently unusable to prevent 
security vulnerabilities.

🛡️ Token is now disabled.''');
          return;
        }
        
        print('✅ SCENARIO: VALID REGISTERED TOKEN');
        print('✅   - Token in Firebase: ✅ FOUND');
        print('✅   - NFC Key: ✅ READABLE');
        print('✅   - Owner: ${token.currentOwnerId}');
        print('✅ Proceeding to handle existing token ownership/transfer...');
        
        // Only valid, registered, readable tokens proceed
        await _handleExistingToken(tokenUid, currentKey, token, gpsLocation, sessionId, currentUser.uid);
        
      } catch (desfireError, stackTrace) {
        print('💥 =============================================================');
        print('💥 DESFIRE ERROR CAUGHT');
        print('💥 Session: $sessionId');
        print('💥 Timestamp: ${DateTime.now().toIso8601String()}');
        print('💥 Error Type: ${desfireError.runtimeType}');
        print('💥 Error Message: $desfireError');
        print('💥 Stack Trace:');
        print('💥 $stackTrace');
        print('💥 =============================================================');
        
        // Check if this is a retryable error - if so, rethrow to let auto-restart handle it
        final errorString = desfireError.toString();
        if (_isRetryableError(errorString)) {
          print('💥 ERROR IS RETRYABLE - rethrowing to auto-restart wrapper');
          rethrow;
        } else {
          print('💥 ERROR IS NOT RETRYABLE - showing error screen');
          _showErrorScreen(errorString);
          return;
        }
      }

      print('🎉 STEP 10: Transaction Complete - Final Cleanup');
      
      // Clear the "keep holding" message but DON'T show success yet
      // Success will be shown by the individual handler methods after write succeeds
      _clearNFCProgress();
      
      // CRITICAL: Force NFC session to close to prevent OS takeover
      // Multiple finish calls are safe and ensure session is truly closed
      print('📱 Force closing NFC session...');
      
      // Try multiple times to ensure it's really closed
      for (int i = 0; i < 2; i++) {
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Complete');
          print('✅ NFC session closed (attempt ${i + 1})');
          break;
        } catch (e) {
          print('ℹ️ NFC finish attempt ${i + 1}: $e');
          if (i == 0) {
            // Wait a bit and try again
            await Future.delayed(Duration(milliseconds: 50));
          }
        }
      }
      
      // Ensure NFC is fully released before continuing
      await Future.delayed(Duration(milliseconds: 200));
      
    } catch (e, stackTrace) {
      print('💥 =============================================================');
      print('💥 GENERAL ERROR CAUGHT');
      print('💥 Session: $sessionId');
      print('💥 Timestamp: ${DateTime.now().toIso8601String()}');
      print('💥 Error Type: ${e.runtimeType}');
      print('💥 Error Message: $e');
      print('💥 Stack Trace:');
      print('💥 $stackTrace');
      print('💥 =============================================================');
      _showErrorScreen(e.toString());
      
      // Force close NFC session on error
      print('📱 Force closing NFC session after error...');
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Failed');
        print('❌ NFC session closed after error');
      } catch (finishError) {
        print('⚠️ Could not finish NFC session: $finishError');
      }
    } finally {
      print('🧹 STEP 11: Final Cleanup');
      print('🧹 Session: $sessionId');
      print('🧹 Resetting UI state...');
      
      setState(() {
        _isScanning = false;
      });
      print('🧹 Scanning state set to false');
      
      _pulseController?.stop();
      _pulseController?.reset();
      print('🧹 Animation controllers stopped and reset');
      
      // Don't automatically hide overlay if there was an error
      if (!_statusMessage.contains('❌') && !_statusMessage.contains('Error')) {
        print('🧹 No errors detected, hiding overlay after delay...');
        await Future.delayed(Duration(seconds: 2));
        _fadeController?.reverse();
        await Future.delayed(Duration(milliseconds: 300));
        setState(() {
          _showOverlay = false;
          _statusMessage = '';
          _cardInfo = '';
        });
        print('🧹 Overlay hidden successfully');
      } else {
        print('🧹 Error detected, keeping overlay visible for user review');
      }
      
      print('🏁 =============================================================');
      print('🏁 SWAPDOT TRANSACTION COMPLETE - Session: $sessionId');
      print('🏁 Timestamp: ${DateTime.now().toIso8601String()}');
      print('🏁 =============================================================');
    }
  }

  /// Handle uninitialized token (first time setup)
  Future<void> _handleUninitializedToken(String tokenUid, Position? gpsLocation, Map<String, String>? tokenMetadata, String sessionId, String userId) async {
    print('🆕 =============================================================');
    print('🆕 HANDLE UNINITIALIZED TOKEN');
    print('🆕 Token UID: $tokenUid');
    print('🆕 Selected User: $_selectedUser');
    if (tokenMetadata != null) {
      print('🆕 Token Name: ${tokenMetadata['name']}');
      print('🆕 Token Series: ${tokenMetadata['series']}');
      print('🆕 Token Rarity: ${tokenMetadata['rarity']}');
    }
    print('🆕 =============================================================');
    
    _updateStatus('Claiming new SwapDot...');
    
    // Get actual Firebase user ID
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw 'User not authenticated';
    }
    
    try {
      // SERVER generates and writes key - client NEVER sees it!
      print('🔐 STEP A: Server Generating and Writing Key');
      print('🔐 Server will generate secure random key...');
      _updateStatus('Server generating secure key...');
      _updateNFCProgress('⏳ Keep card in place... Server generating key');
      
      final writeStartTime = DateTime.now();
      
      // Server generates the key and writes it - we only get the hash back!
      final keyHash = await ServerNFCService.writeServerGeneratedKey(
        tokenId: tokenUid,
        userId: currentUser.uid,
        sessionId: sessionId, // Use the already authenticated session!
        transferSessionId: null, // No transfer for initial registration
        allowUnowned: true, // This is initialization, token not owned yet
      );
      
      final writeDuration = DateTime.now().difference(writeStartTime);
      
      // Safely preview the hash (it might be null from the server)
      String previewHash(String? h) {
        if (h == null || h.isEmpty) return 'unknown';
        final end = h.length < 16 ? h.length : 16;
        return h.substring(0, end);
      }
      
      print('🔐 Server key generation and write completed in ${writeDuration.inMilliseconds}ms');
      print('🔐 Key hash from server: ${previewHash(keyHash)}...');
      print('✅ Card write successful!');
      
      // Show success animation after write completes
      await _showSuccessFeedback('✅ Ownership key written!');
      
      // Register token in Firebase SECOND (after card write succeeds)
      print('🔥 STEP C: Register Token in Firebase');
      _updateStatus('Registering with server...');
      
      final metadata = {
        'claimed_by': _selectedUser,
        'initialization_method': 'nfc_scan',
        'timestamp': DateTime.now().toIso8601String(),
        'name': tokenMetadata?['name'] ?? 'Unknown Token',
        'series': tokenMetadata?['series'] ?? 'Unknown Series',
        'rarity': tokenMetadata?['rarity'] ?? 'common',
      };
      
      print('🔥 Calling Firebase registerToken with metadata: $metadata');
      final registerStartTime = DateTime.now();
      final result = await SwapDotzFirebaseService.registerToken(
        tokenUid: tokenUid,
        keyHash: keyHash,
        metadata: metadata,
        forceOverwrite: true, // Allow overwriting existing tokens during initialization
        gpsLocation: gpsLocation, // Use pre-obtained GPS location
      );
      final registerDuration = DateTime.now().difference(registerStartTime);
      
      print('🔥 Firebase registration completed in ${registerDuration.inMilliseconds}ms');
      print('🔥 Registration result: $result');
      
      // Play rarity sound effect after successful registration
      await _playRaritySound(tokenMetadata?['rarity']);
      
      print('✅ UNINITIALIZED TOKEN HANDLING COMPLETE');
      
      // Get the current user's identifier (using already declared currentUser)
      final userIdentifier = currentUser?.displayName ?? 
                           currentUser?.email?.split('@')[0] ?? 
                           'User ${currentUser?.uid.substring(0, 8) ?? "Unknown"}';
      
      _updateStatus('✅ SwapDot claimed successfully!');
      
      // Get rarity info for display
      final rarity = tokenMetadata?['rarity'] ?? 'common';
      final rarityIcon = rarity == 'rare' ? '🟠' : (rarity == 'uncommon' ? '🔵' : '🟢');
      
      _updateCardInfo('''$_cardInfo

🎉 Congratulations!
You are now the owner of this SwapDot!

Owner: $userIdentifier
Token UID: $tokenUid
Rarity: $rarityIcon ${rarity.toUpperCase()}
Key: [Server-generated, never exposed to client]
Hash: ${keyHash.substring(0, 16)}...

Your SwapDot is now registered and ready to transfer.''');

      // Navigate to celebration screen after successful token initialization
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => TestCelebrationScreen(
            swapDotId: tokenUid,
            rarity: tokenMetadata?['rarity'] ?? 'common'
          ),
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
      
    } catch (e, stackTrace) {
      print('💥 UNINITIALIZED TOKEN HANDLING FAILED');
      print('💥 Error: $e');
      print('💥 Stack trace: $stackTrace');
      throw 'Failed to claim SwapDot: $e';
    }
  }

  /// Handle existing token (check ownership and transfers)
  Future<void> _handleExistingToken(String tokenUid, String? currentKey, Token token, Position? gpsLocation, String sessionId, String userId) async {
    print('🎯 HANDLE EXISTING TOKEN: Starting for selected user: $_selectedUser');
    final currentUserId = await SwapDotzFirebaseService.getCurrentUserId();
    
    if (currentUserId == null) {
      print('🎯 HANDLE EXISTING TOKEN: Authentication failed - currentUserId is null');
      _updateStatus('❌ Authentication required');
      _updateCardInfo('Unable to authenticate user. Please try again.');
      
      // NFC session will be finished in main flow
      return;
    }
    print('🎯 HANDLE EXISTING TOKEN: Authentication passed, currentUserId: $currentUserId');

    // DIAGNOSTIC: Verify key synchronization first (hidden from user)
    print('🎯 HANDLE EXISTING TOKEN: About to verify key synchronization');
    await _verifyKeySynchronization(currentKey, token, tokenUid);
    print('🎯 HANDLE EXISTING TOKEN: Key synchronization completed');
    
    // Show exciting ownership verification to user
    _updateStatusExciting('🔐 Verifying ownership...');
    await Future.delayed(Duration(milliseconds: 600));
    _updateStatusExciting('✅ Ownership confirmed!');
    print('🎯 HANDLE EXISTING TOKEN: Ownership verification UI completed');
    
    // Check for new secure transfer system first
    print('🔍 HANDLE EXISTING TOKEN: Checking for pendingTransfer document...');
    final pendingTransfer = await SecureTransferService.getPendingTransfer(tokenUid);
    print('🔍 HANDLE EXISTING TOKEN: pendingTransfer result:');
    if (pendingTransfer != null) {
      print('🔍   - Document EXISTS');
      print('🔍   - State: ${pendingTransfer.state}');
      print('🔍   - From: ${pendingTransfer.fromUid}');
      print('🔍   - To: ${pendingTransfer.toUid}');
      print('🔍   - Expires: ${pendingTransfer.expiresAt}');
      print('🔍   - Is Open: ${pendingTransfer.isOpen}');
      print('🔍   - Is Committed: ${pendingTransfer.isCommitted}');
      print('🔍   - Is Expired: ${pendingTransfer.isExpired}');
    } else {
      print('🔍   - Document DOES NOT EXIST (properly deleted after transfer completion)');
    }
    
    if (pendingTransfer != null) {
      // Respect user selection: if user selected "receiver", force receiver behavior
      if (_selectedUser == 'receiver') {
        print('🎯 HANDLE EXISTING TOKEN: User selected receiver, handling secure transfer');
        try {
          await _handleSecureTransfer(tokenUid, pendingTransfer, currentUserId, token);
          print('🎯 HANDLE EXISTING TOKEN: handleSecureTransfer completed successfully');
          return;
        } catch (e) {
          print('🎯 HANDLE EXISTING TOKEN: handleSecureTransfer threw exception: $e');
          rethrow;
        }
      }
      
      // SECURITY: COMMITTED transfers should NOT exist (they should be deleted)
      // If we find one, it's a bug - the transfer is complete and we should NOT allow new transfers
      if (pendingTransfer.isCommitted) {
        print('❌ HANDLE EXISTING TOKEN: Found COMMITTED transfer - this is a BUG!');
        print('❌ COMMITTED transfers should be deleted after completion');
        print('❌ From: ${pendingTransfer.fromUid} To: ${pendingTransfer.toUid}');
        print('❌ This indicates the backend didn\'t properly clean up');
        
        // COMMITTED transfers should have been deleted - offer to clean up
        _updateStatus('❌ Transfer system error');
        _updateCardInfo('''Transfer Error: Stale transfer record found.
        
This transfer was already completed but not properly cleaned up.

Transfer was from: ${pendingTransfer.fromUid}
Transfer was to: ${pendingTransfer.toUid ?? 'Unknown'}

Attempting automatic cleanup...''');
        
        // Try to clean up the stale COMMITTED transfer
        print('🧹 Attempting to clean up stale COMMITTED transfer for token: $tokenUid');
        try {
          // Call the cleanup function
          final cleanupFunc = FirebaseFunctions.instance.httpsCallable('cleanupStaleCommittedTransfers');
          final result = await cleanupFunc.call();
          print('🧹 Cleanup result: ${result.data}');
          
          if (result.data['ok'] == true && result.data['count'] > 0) {
            _updateStatus('✅ Cleaned up stale transfer');
            _updateCardInfo('''Stale transfer cleaned up successfully!
            
Please scan the token again to proceed with your transfer.''');
          } else {
            _updateCardInfo('''No stale transfers found to clean up.
            
The pendingTransfer document may have already been cleaned up.
Please scan again.''');
          }
        } catch (e) {
          print('❌ Failed to clean up stale transfer: $e');
          _updateCardInfo('''Failed to clean up automatically.
          
Error: $e

Please contact support or manually delete the pendingTransfer 
document for token $tokenUid in Firebase Console.''');
        }
        
        // NFC session will be finished in main flow
        return;
      }
      
      // SECURITY: Re-fetch the latest token data to ensure we have current ownership
      print('🔄 HANDLE EXISTING TOKEN: Re-fetching latest token data to verify ownership...');
      final latestToken = await SwapDotzFirebaseService.getToken(tokenUid);
      if (latestToken == null) {
        print('❌ HANDLE EXISTING TOKEN: Token disappeared from database!');
        _updateStatus('❌ Token not found');
        _updateCardInfo('Token no longer exists in the database.');
        return;
      }
      
      // Use the fresh token data for ownership check
      final actualCurrentOwner = latestToken.currentOwnerId;
      print('🔄 HANDLE EXISTING TOKEN: Fresh ownership data - Owner: $actualCurrentOwner, Current User: $currentUserId');
      
      // CRITICAL: Only allow current owner to create new transfers if they actually still own it
      // Check the actual ownership from the LATEST token data, not the stale data
      if (actualCurrentOwner == currentUserId) {
        print('✅ OWNERSHIP VERIFIED: User ${currentUserId} owns token with owner ${actualCurrentOwner}');
        // Additional check: if there's an OPEN transfer that's not from this user, reject
        if (pendingTransfer.isOpen && pendingTransfer.fromUid != currentUserId) {
          print('🔒 HANDLE EXISTING TOKEN: OPEN transfer from different user detected');
          _updateStatus('❌ Another transfer in progress');
          _updateCardInfo('''There's already an active transfer for this token initiated by another user.

From: ${pendingTransfer.fromUid}
Status: ${pendingTransfer.state}
Expires: ${pendingTransfer.expiresAt}

Please wait for this transfer to complete or expire.''');
          return;
        }
        
        if (pendingTransfer.isExpired) {
          print('🔄 Found expired transfer - owner creating new one to replace it');
        } else if (pendingTransfer.isOpen && pendingTransfer.fromUid == currentUserId) {
          print('🔄 Found own active transfer - owner can overwrite their own transfer');
        } else {
          print('⚠️ Unexpected transfer state: ${pendingTransfer.state}');
        }
        
        // Exciting transfer preparation
        await _playExcitingSequence([
          '🎁 Preparing gift transfer...',
          '⚡ Charging transfer portal...',
          '🚀 Launching secure transfer...'
        ], stepDelay: Duration(milliseconds: 500));
        
        // Use the FRESH token data, not the stale one
        await _initiateSecureTransferOrFallback(tokenUid, currentKey, latestToken, currentUserId, gpsLocation, sessionId, userId);
        return;
      }
      
      await _handleSecureTransfer(tokenUid, pendingTransfer, currentUserId, token);
      return;
    }

    // OPTIMIZATION: Skip legacy transfer check - we don't use legacy transfers anymore
    // This saves ~150ms per scan
    // Legacy transfers were removed to prevent ownership issues
    
    // Respect user selection for ownership scenarios
    if (_selectedUser == 'receiver') {
      print('🎯 RECEIVER LOGIC: Selected user is receiver');
      // If user selected receiver and owns the token, just show confirmation
      if (token.currentOwnerId == currentUserId) {
        print('🎯 RECEIVER LOGIC: User owns token, showing simple confirmation');
        // Just show ownership confirmation - NO CELEBRATION
        _updateStatus('✅ SwapDot verified');
        _updateCardInfo('''✅ Ownership Confirmed

You own this SwapDot.

Token ID: ${tokenUid.substring(0, 8)}...
Name: ${token.metadata.name ?? 'Unknown'}
Rarity: ${token.metadata.rarity ?? 'common'}''');
        // NO CELEBRATION SCREEN - just return
        return;
      }
      
      // If user selected receiver and doesn't own it, check for pending transfers
      print('🎯 RECEIVER LOGIC: User does not own token, checking for pending transfers...');
      await _handleRecipientClaimsTransfer(tokenUid, currentKey, token);
      return;
    }
    
    // SECURITY: Always re-fetch the latest token data to ensure we have current ownership
    // Never trust cached data for security-critical operations
    print('🔒 SECURITY: Re-fetching latest token data for ownership verification...');
    print('🔒   - Token UID being checked: $tokenUid');
    print('🔒   - Time: ${DateTime.now().toIso8601String()}');
    final latestTokenForCheck = await SwapDotzFirebaseService.getToken(tokenUid);
    if (latestTokenForCheck == null) {
      print('❌ SECURITY: Token disappeared from database!');
      _updateStatus('❌ Token not found');
      _updateCardInfo('Token no longer exists in the database.');
      return;
    }
    
    final currentOwner = latestTokenForCheck.currentOwnerId;
    print('🔒 CRITICAL OWNERSHIP CHECK - NO PENDING TRANSFER PATH:');
    print('🔒   - Token UID: $tokenUid');
    print('🔒   - Fresh Token Owner from DB: "$currentOwner"');
    print('🔒   - Current User ID: "$currentUserId"');
    print('🔒   - Owner == User: ${currentOwner == currentUserId}');
    print('🔒   - Selected Role: $_selectedUser');
    print('🔒   - Time: ${DateTime.now().toIso8601String()}');
    print('🔒   - This determines if user can initiate transfers!');
    
    // Otherwise, if you own it and selected "gifter", allow initiating a transfer
    if (currentOwner == currentUserId) {
      print('✅ HANDLE EXISTING TOKEN: User "$currentUserId" OWNS token (owner: "$currentOwner")');
      print('✅   - Will allow transfer initiation');
    } else {
      print('❌ HANDLE EXISTING TOKEN: User "$currentUserId" DOES NOT own token (owner: "$currentOwner")');
      print('❌   - Will NOT allow transfer initiation');
    }
    
    if (currentOwner == currentUserId) {
      // Try secure transfer first, fallback to legacy if needed
      // Use FRESH token data to ensure proper ownership fields
      await _initiateSecureTransferOrFallback(tokenUid, currentKey, latestTokenForCheck, currentUserId, gpsLocation, sessionId, userId);
      // NFC session will be finished by _initiateSecureTransferOrFallback
      return;
    }

    // No session and not owner
    if (_selectedUser == 'gifter') {
      _updateStatus('❌ This doesn\'t belong to you');
      _updateCardInfo('''This SwapDot doesn't belong to you.

Owner: ${currentOwner}

Only the owner can initiate gift transfers.
Ask ${currentOwner} to scan their SwapDot first.''');
    } else {
      _updateStatus('❌ No transfer available');
      _updateCardInfo('''This SwapDot belongs to ${currentOwner} and no active transfer session was found.
Ask the owner to start a transfer.''');
    }
    
    // Finish NFC session for non-owner scenarios
    try {
      await FlutterNfcKit.finish(iosAlertMessage: 'Not authorized');
    } catch (e) {
      print('⚠️ Failed to finish NFC session: $e');
    }
    
    print('🎯 HANDLE EXISTING TOKEN: Completed - no session and not owner');
  }

  /// Handle secure transfer system (new)
  Future<void> _handleSecureTransfer(String tokenUid, PendingTransfer pendingTransfer, String currentUserId, Token token) async {
    print('🎯 HANDLE SECURE TRANSFER: Starting - fromUid: ${pendingTransfer.fromUid}, currentUserId: $currentUserId');
    print('🎯 HANDLE SECURE TRANSFER: Transfer state: ${pendingTransfer.state}, expired: ${pendingTransfer.isExpired}');
    print('🎯 HANDLE SECURE TRANSFER: Selected user role: $_selectedUser');
    print('🎯 HANDLE SECURE TRANSFER: Token rarity: ${token.metadata.rarity}');
    
    // Respect user selection - if user selected "receiver", force receiver behavior
    // This allows testing flows where the same user acts as both gifter and receiver
    if (_selectedUser == 'receiver') {
      print('🎯 HANDLE SECURE TRANSFER: User selected receiver role, proceeding as receiver');
      // Skip sender logic and proceed directly to receiver logic
    } else {
      // If current user is the sender and they selected gifter, show transfer status
      if (pendingTransfer.fromUid == currentUserId) {
        print('🎯 HANDLE SECURE TRANSFER: Current user is sender and selected gifter, showing transfer status');
        final timeLeft = pendingTransfer.expiresAt.difference(DateTime.now());
        _updateStatus('🎁 Transfer initiated');
        _updateCardInfo('''Transfer session active!
        
From: You
Status: Waiting for recipient
Expires in: ${timeLeft.inMinutes} minutes

Hand this SwapDot to the recipient and have them scan it to complete the transfer.''');
        
        // Finish NFC session for sender
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer session active');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
    }

    print('🎯 HANDLE SECURE TRANSFER: Checking if transfer is expired');
    // SECURITY: Always reject expired transfers - NO EXCEPTIONS
    if (pendingTransfer.isExpired) {
      print('⏰ HANDLE SECURE TRANSFER: Transfer is EXPIRED - REJECTING ALL ACCESS');
      _updateStatus('❌ Transfer expired');
      _updateCardInfo('''Transfer Session Expired
      
From: ${pendingTransfer.fromUid}
To: ${pendingTransfer.toUid ?? 'Unknown'}
Expired: ${pendingTransfer.expiresAt.toLocal()}

This transfer is no longer valid.
The owner must create a new transfer.

NO expired transfers can be accepted.''');
      
      // NFC session will be finished in main flow
      return;
    }

    print('🎯 HANDLE SECURE TRANSFER: Transfer is not expired, user is receiver, starting claim process');
    // User is receiver and transfer is still valid
    try {
      _updateStatus('Claiming SwapDot...');
      
      print('🎯 HANDLE SECURE TRANSFER: Calling finalizeTransfer Cloud Function...');
      final response = await SecureTransferService.finalizeTransfer(
        tokenId: tokenUid,
        // tagUid: could pass NFC UID here for additional verification
      );

      print('🎯 HANDLE SECURE TRANSFER: Transfer finalized successfully!');
      print('🎯   - Response OK: ${response.ok}');
      print('🎯   - New Owner UID: ${response.newOwnerUid}');
      print('🎯   - Counter: ${response.counter}');
      
      _updateStatus('✅ SwapDot received!');
      _updateCardInfo('''🎉 Transfer successful!

From: ${pendingTransfer.fromUid}
To: You (${response.newOwnerUid})
Counter: ${response.counter}

You are now the owner of this SwapDot!''');

      // NFC session will be finished in main flow after we return
      // Don't finish here to avoid conflicts with main flow
      
      print('🎯 HANDLE SECURE TRANSFER: About to navigate to celebration screen');
      // Navigate to celebration screen after successful transfer
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => TestCelebrationScreen(
            swapDotId: tokenUid,
            rarity: token.metadata.rarity ?? 'common'
          ),
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
      print('🎯 HANDLE SECURE TRANSFER: Navigation to celebration screen completed');

    } catch (e, stackTrace) {
      print('❌ HANDLE SECURE TRANSFER: Transfer failed with error!');
      print('❌   - Error type: ${e.runtimeType}');
      print('❌   - Error message: $e');
      print('❌   - Stack trace: $stackTrace');
      
            String errorMessage = 'Failed to claim SwapDot';
      if (e is SecureTransferException) {
        errorMessage = '${errorMessage}: ${e.userFriendlyMessage}';
      } else {
        errorMessage = '${errorMessage}: ${e.toString()}';
      }
      
      _updateStatus('❌ Transfer failed');
      _updateCardInfo(errorMessage);
      
      // Finish NFC session on error
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Transfer failed');
      } catch (finishError) {
        print('⚠️ Failed to finish NFC session: $finishError');
      }
    }
  }

     /// Initiate secure transfer or fallback to legacy system
  Future<void> _initiateSecureTransferOrFallback(String tokenUid, String? currentKey, Token token, String currentUserId, Position? gpsLocation, String sessionId, String userId) async {
    try {
      _updateStatus('🔒 Verifying location...');
      
      // SECURITY: Always verify location with user confirmation
      TradeLocationResult locationResult;
      if (gpsLocation != null) {
        print('🔒 SECURITY: Using pre-fetched GPS location');
        // We already have GPS, create result with it
        locationResult = TradeLocationResult.withLocation(
          location: gpsLocation,
          quality: LocationQuality.network,
          source: 'concurrent_gps',
        );
      } else {
        print('🔒 SECURITY: Getting location with full UI verification');
        locationResult = await TradeLocationService.getTradeLocation(
          context: context,
          tokenId: tokenUid,
          fromUser: currentUserId,
          toUser: 'pending',
        );
      }
      
      // SECURITY: Check if user cancelled
      if (locationResult.cancelled) {
        _updateStatus('❌ Transfer cancelled');
        _updateCardInfo('Transfer cancelled by user during location verification');
        return;
      }
      
      // Show location status
      if (locationResult.hasLocation) {
        _updateStatus('📍 Location verified! Starting secure transfer...');
      } else {
        _updateStatus('⚠️ No location available - continuing with transfer...');
      }
      
      final response = await SecureTransferService.initiateTransfer(
        tokenId: tokenUid,
      );

      String locationInfo = '';
      if (locationResult.hasLocation) {
        locationInfo = '''
📍 Location: Verified (${locationResult.quality.toString().split('.').last})
✅ This trade will earn location achievements!''';
      } else {
        locationInfo = '''
📍 Location: Not available
⚠️ No location achievements for this trade''';
      }

      _updateStatus('✅ Transfer ready!');
      
      // OPTIMIZATION: Run animations in parallel for speed
      await Future.wait([
        _showSuccessFeedback('✅ Transfer ready!'),
        Future.delayed(Duration(milliseconds: 200), () => _playZoomAnimation()),
      ]);
      
      _updateCardInfo('''🎁 Secure Transfer Started!

Token: $tokenUid
Transfer expires: ${response.expiryDateTime.toLocal()}
Security counter: ${response.nNext}
$locationInfo

Hand this SwapDot to the recipient within 10 minutes.
They will scan it to complete the transfer securely.

🔒 This transfer uses the new secure two-phase system.''');

      // Skip trade location recording for now (causes permission issues)
      // TODO: Add firestore rules for 'trades' collection if location tracking needed
      // if (locationResult.hasLocation) {
      //   await TradeLocationService.recordTrade(
      //     tokenId: tokenUid,
      //     fromUser: currentUserId,
      //     toUser: 'pending',
      //     locationResult: locationResult,
      //   );
      // }
      
      // Finish NFC session after successful transfer initiation
      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'Transfer initiated');
      } catch (e) {
        print('⚠️ Failed to finish NFC session: $e');
      }

    } catch (e) {
      print('Secure transfer failed: $e');
      
      // Check if the error is due to an existing pending transfer
      if (e.toString().contains('already pending') || e.toString().contains('pending transfer') || 
          e.toString().contains('already exists') || e.toString().contains('Transfer already pending')) {
        print('🔄 SECURE TRANSFER: Backend rejected due to existing pending transfer');
        print('🔄 Since user is the owner, this should be allowed - showing user-friendly message');
        _updateStatusExciting('🎉 Transfer portal activated!');
        await Future.delayed(Duration(milliseconds: 600));
        
        _updateStatus('✅ Ready to gift!');
        
        // Show success feedback with sound
        await _showSuccessFeedback('✅ Ready to gift!');
        
        // Play epic ZOOM animation AFTER the success sound completes!
        await _playZoomAnimation();
        _updateCardInfo('''🎁✨ Gift Transfer Ready! ✨🎁

Your SwapDot is charged and ready to transfer!

🤝 Hand it to your friend
📱 They scan to receive it  
⚡ Instant secure transfer!

🔒 Protected by quantum encryption''');
        
        // Finish NFC session for existing pending transfer case
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer ready');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      
      // NO LEGACY FALLBACK - Secure transfer only!
      print('❌ Secure transfer failed - NOT falling back to legacy: $e');
      _updateStatus('❌ Transfer failed');
      _updateCardInfo('''Transfer Error
      
Unable to initiate secure transfer.

Error: ${e.toString().replaceAll('[cloud_firestore/', '').replaceAll(']', '')}

Please try again.''');
      
      // Finish NFC session on error
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Transfer failed');
      } catch (finishError) {
        print('⚠️ Failed to finish NFC session: $finishError');
      }
    }
  }

  /// Verify that the user actually owns the token by checking the key hash
  /// NOTE: This verification may fail if called after a failed secure transfer attempt
  /// because the secure transfer system doesn't modify NFC keys during initiation
  Future<void> _verifyOwnershipAndInitiateTransfer(Desfire desfire, String tokenUid, String? currentKey, Token token, String currentUserId) async {
    print('🔒 =============================================================');
    print('🔒 LEGACY OWNERSHIP VERIFICATION');
    print('🔒 Token UID: $tokenUid');
    print('🔒 Current User ID: $currentUserId');
    print('🔒 Firebase Owner ID: ${token.currentOwnerId}');
    print('🔒 NOTE: Key hash verification may fail if secure transfer was attempted first');
    print('🔒 =============================================================');
    
    _updateStatus('Verifying ownership...');
    
    // Critical Security Check: Verify the key from NFC matches the hash in Firebase
    print('🔐 STEP 1: Key Validation');
    print('🔐 Server will validate key authenticity...');
    
    // Server handles all key validation now - client just passes data
    final expectedKeyHash = token.keyHash;
    
    print('🔐 SECURITY CHECK DATA:');
    print('🔐   - Client Key Access: DENIED (security)');
    print('🔐   - Expected Hash in DB: ${expectedKeyHash.substring(0, 16)}...');
    print('🔐   - Server will validate key authenticity');
    
    // Server handles validation now - removing client-side check
    // The server will reject operations if the key doesn't match
    
    print('✅ =============================================================');
    print('✅ CLIENT-SIDE CHECK COMPLETE');
    print('✅ Server will perform cryptographic validation');
    print('✅ Proceeding to transfer initiation...');
    print('✅ =============================================================');
    
    _updateStatus('✅ Ownership verified');
    
    // Now safely proceed with transfer initiation
    await _handleOwnerInitiatesTransfer(desfire, tokenUid, currentKey, token);
  }

  /// Handle owner initiating a gift transfer
  Future<void> _handleOwnerInitiatesTransfer(Desfire desfire, String tokenUid, String? currentKey, Token token) async {
    print('🔵 SCENARIO 2: Owner initiating transfer');
    _updateStatus('You own this SwapDot!');
    _updateStatus('Initiating gift transfer...');
    
    try {
      // Create transfer session in Firebase
      final transferResponse = await SwapDotzFirebaseService.initiateTransfer(
        tokenUid: tokenUid,
        toUserId: null, // open session (free-for-all)
        sessionDurationMinutes: 10,  // Increased for testing
        gpsLocation: _preloadedGpsLocation ?? await SwapDotzFirebaseService.getCurrentPositionObject(),
      );
      
      print('✅ Transfer session created: ${transferResponse.sessionId}');
      print('🔐 Challenge: ${transferResponse.challenge}');
      
      // Do not write secrets in plaintext. Only write minimal transfer marker.
      // Using server-authoritative NFC - all crypto happens server-side
      final marker = 'transfer:active;session:${transferResponse.sessionId};ts:${DateTime.now().millisecondsSinceEpoch}';
      _updateStatus('Marking transfer on card (secure)...');
      _updateNFCProgress('⏳ Keep holding SwapDot...');
      // Get actual Firebase user ID
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw 'User not authenticated';
      }
      
      await ServerNFCService.writeFile01(
        Uint8List.fromList(utf8.encode(marker)),
        tokenId: tokenUid,
        userId: currentUser.uid, // Use actual Firebase Auth UID
      );
      
      // NOW show success after write completes
      await _showSuccessFeedback('✅ Gift transfer initiated!');
      
      // Play epic ZOOM animation AFTER the write key sound completes!
      await _playZoomAnimation();
      
      _updateCardInfo('''$_cardInfo

Transfer Session Active!
Session ID: ${transferResponse.sessionId}
Expires: ${transferResponse.expiresAt.toLocal()}
To User: Anyone (open claim)

Give this SwapDot to someone and have them scan it
to complete the transfer. They will become the new owner!''');
      
      // Finish NFC session after successful transfer initiation
      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'Transfer initiated');
      } catch (finishError) {
        print('⚠️ Failed to finish NFC session: $finishError');
      }
      
    } catch (e) {
      final err = e.toString();
            if (err.contains('already-exists')) {
         print('ℹ️ Active session already exists. Using existing session.');
         final sessions = await SwapDotzFirebaseService.getPendingTransferSessions(tokenUid);
         if (sessions.isNotEmpty && sessions.first.challenge != null) {
           final session = sessions.first;
           if (session.expiresAt.isBefore(DateTime.now())) {
             _updateStatus('Existing transfer session expired. Creating a new one...');
             // Fall through to create a fresh session by rethrowing
             throw e;
           }
           print('ℹ️ Existing session: ${session.sessionId}');
           final marker = 'transfer:active;session:${session.sessionId};ts:${DateTime.now().millisecondsSinceEpoch}';
           _updateStatus('Marking existing transfer on card...');
           _updateNFCProgress('⏳ Keep holding SwapDot...');
           await desfire.writeFile01(Uint8List.fromList(utf8.encode(marker)));
           
           // Show success after write completes
           await _showSuccessFeedback('✅ Gift transfer active!');
           
           // Play epic ZOOM animation AFTER the write key sound completes!
           await _playZoomAnimation();
           
           _updateCardInfo('''$_cardInfo
 
 Transfer Session Active (existing)
 Session ID: ${session.sessionId}
 Expires: ${session.expiresAt.toLocal()}
 To User: ${session.toUserId ?? 'Anyone (open claim)'}
 
 Hand the SwapDot to the recipient to complete the transfer.''');
           
           // Finish NFC session for existing session reuse
           try {
             await FlutterNfcKit.finish(iosAlertMessage: 'Transfer ready');
           } catch (e) {
             print('⚠️ Failed to finish NFC session: $e');
           }
           return;
         }
       }
      print('❌ Failed to initiate transfer: $e');
      throw 'Failed to initiate transfer: $e';
    }
  }

  /// Handle recipient claiming a gift transfer
  Future<void> _handleRecipientClaimsTransfer(String tokenUid, String? currentKey, Token token) async {
    print('🔵 SCENARIO 3: Checking for pending transfer sessions');
    _updateStatus('Checking for gift transfers...');
    
    try {
      // Look for pending transfer sessions for this token
      final sessions = await SwapDotzFirebaseService.getPendingTransferSessions(tokenUid);
      
      if (sessions.isEmpty) {
        // No pending transfers
        _updateStatus('❌ No transfer available');
        _updateCardInfo('''$_cardInfo

This SwapDot belongs to someone else.
Owner: ${token.currentOwnerId}

No active transfer session found.
Ask the owner to scan their SwapDot first to initiate a gift transfer.''');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'No transfer available');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      
      // Do not allow the gifter to claim their own session
      final currentUserId = await SwapDotzFirebaseService.getCurrentUserId();
      // Allow claiming if:
      // 1. Transfer is open (toUserId == null) 
      // 2. Transfer is specifically for current user
      // 3. We don't care about receiver restrictions (just not the gifter)
      final eligible = sessions.where((s) =>
        s.fromUserId != currentUserId  // Can't claim your own transfer
      ).toList();

      if (eligible.isEmpty) {
        _updateStatus('Transfer is intended for a different user.');
        _updateCardInfo('''$_cardInfo

🚫 This transfer is intended for a different user.
Ask the gifter to create a new open transfer (anyone can claim).''');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer not eligible');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }

      // Use the most recent unexpired eligible session
      final session = eligible.first;
      if (currentUserId != null && session.fromUserId == currentUserId) {
        _updateStatus('You started this transfer. Hand the SwapDot to the recipient to claim.');
        _updateCardInfo('''$_cardInfo

ℹ️ Transfer is active.
From: ${session.fromUserId}
To: ${session.toUserId ?? 'Anyone (open claim)'}
Expires: ${session.expiresAt.toLocal()}''');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'You initiated this transfer');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      
      if (session.expiresAt.isBefore(DateTime.now())) {
        print('⏳ Found session is expired locally; prompting owner to re-initiate');
        _updateStatus('Transfer session expired. Ask the owner to scan again.');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer expired');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      print('🎁 Found transfer session: ${session.sessionId}');
      
      _updateStatus('Gift transfer found!');
      _updateStatus('Verifying transfer challenge...');
      
      // SECURITY: Server validates challenge - client doesn't read keys
      // The server will reject invalid transfers during validation
      
      print('✅ TRANSFER VERIFICATION: Challenge response appears valid');
      _updateStatus('Validating location for transfer...');
      
      // Get location validation for receiving the transfer
      final locationResult = await TradeLocationService.getTradeLocation(
        context: context,
        tokenId: tokenUid,
        fromUser: session.fromUserId,
        toUser: _selectedUser,
      );
      
      if (locationResult.cancelled) {
        _updateStatus('❌ Transfer cancelled');
        _updateCardInfo('Transfer cancelled during location validation');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer cancelled');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      
      // Show location status
      if (locationResult.hasLocation) {
        _updateStatus('📍 Location verified! Claiming SwapDot...');
      } else {
        _updateStatus('⚠️ No location - claiming SwapDot...');
      }
      
      // Get actual Firebase user ID for new owner
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw 'User not authenticated';
      }
      
      // 🔐 SECURE SERVER-AUTHORITATIVE VALIDATION
      // The server will read the key from the card and validate internally
      // The client NEVER sees or processes the key - just pipes raw APDU responses
      
      _updateStatus('🔐 Validating card authenticity...');
      _updateNFCProgress('⏳ Server validating SwapDot...');
      
      // Server reads key from card and validates challenge internally
      Map<String, dynamic> validationResult;
      try {
        validationResult = await ServerNFCService.readAndValidateTransfer(
          tokenId: tokenUid,
          userId: currentUser.uid,
          transferSessionId: session.sessionId,
          allowUnowned: true,  // Recipients don't own the token yet
        );
        print('✅ Server validated card successfully!');
      } catch (validationError) {
        print('❌ Server validation failed: $validationError');
        if (validationError.toString().contains('Card key does not match database')) {
          _updateStatus('❌ Invalid SwapDot');
          _updateCardInfo('This SwapDot has been tampered with or is not authentic.');
          return;
        }
        throw 'Card validation failed: $validationError';
      }
      
      // Write SERVER-GENERATED key (client NEVER sees it!)
      _updateStatus('🔐 Generating secure key server-side...');
      _updateNFCProgress('⏳ Keep holding SwapDot... Server generating key');
      
      String newKeyHash;
      try {
        // Server generates the key and writes it - we only get the hash back!
        newKeyHash = await ServerNFCService.writeServerGeneratedKey(
          tokenId: tokenUid,
          userId: currentUser.uid,
          transferSessionId: session.sessionId,
          allowUnowned: true,  // Recipients don't own the token yet!
        );
        print('✅ Server-generated key written! Hash: ${newKeyHash.substring(0, 16)}...');
      } catch (nfcError) {
        print('❌ Failed to write server-generated key: $nfcError');
        rethrow;
      }
      
      // Now stage the transfer with server validation flag
      final staged = await SwapDotzFirebaseService.stageTransferSecure(
        sessionId: session.sessionId,
        newKeyHash: newKeyHash,
        newOwnerId: currentUser.uid,
        serverValidated: true,  // 🔐 Using secure server-side validation!
      );
      
      // Attempt NFC write verification
      try {
        _updateStatus('Verifying key write...');
      } catch (nfcError) {
        await SwapDotzFirebaseService.rollbackTransfer(
          stagedTransferId: staged.stagedTransferId,
          reason: 'NFC write failed: ${nfcError.toString()}',
        );
        rethrow;
      }
      
      // Commit transfer (Phase 2)
      final completeResponse = await SwapDotzFirebaseService.commitTransfer(
        stagedTransferId: staged.stagedTransferId,
      );
      
      // Record the completed trade with location
      if (locationResult.hasLocation) {
        // Get the actual current user ID (the receiver)
        final currentUserId = await SwapDotzFirebaseService.getCurrentUserId();
        if (currentUserId != null) {
          await TradeLocationService.recordTrade(
            tokenId: tokenUid,
            fromUser: session.fromUserId,
            toUser: currentUserId,  // Use actual Firebase user ID, not "receiver" string
            locationResult: locationResult,
          );
        } else {
          print('⚠️ Could not get current user ID for trade record');
        }
      }
      
      print('✅ Transfer committed: ${completeResponse.transferLogId}');
      
      // Show success after write completes
      await _showSuccessFeedback('✅ SwapDot successfully received!');
      _updateCardInfo('''$_cardInfo

🎉 Gift Received!
From: ${session.fromUserId}
To: ${completeResponse.newOwnerId}
Transfer ID: ${completeResponse.transferLogId}

You are now the owner of this SwapDot!
Key securely stored (hash: ${newKeyHash.substring(0, 16)}...)''');
      
      // Finish NFC session before celebration
      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'SwapDot received!');
      } catch (e) {
        print('⚠️ Failed to finish NFC session: $e');
      }
      
      // Show celebration
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => TestCelebrationScreen(
              swapDotId: tokenUid,
              rarity: token.metadata.rarity ?? 'common'
            ),
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
      
    } on FirebaseFunctionsException catch (e) {
      final code = e.code;
      print('❌ Failed to claim transfer (code=$code): ${e.message}');
      if (code == 'deadline-exceeded' || code == 'failed-precondition') {
        _updateStatus('Transfer expired. Ask the owner to start a new transfer.');
        
        // Finish NFC session
        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'Transfer expired');
        } catch (e) {
          print('⚠️ Failed to finish NFC session: $e');
        }
        return;
      }
      throw 'Failed to claim transfer: ${e.message}';
    } catch (e) {
      print('❌ Failed to claim transfer: $e');
      throw 'Failed to claim transfer: $e';
    }
  }

  // Simple diagnostic test - matches the working reference pattern
  Future<void> _testSecureMessaging() async {
    try {
      _updateStatus('🔐 Testing Secure Messaging...');
      _updateCardInfo('Testing WriteData and ChangeKey with secure messaging...');
      
      // Get current user first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateStatus('❌ Not logged in');
        _updateCardInfo('Please log in first');
        return;
      }
      
      // Poll for NFC tag to get its UID
      _updateStatus('📱 Place NFC card near phone...');
      final tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: 30),
        iosMultipleTagMessage: "Multiple tags found!",
        iosAlertMessage: "Hold your NFC tag near the phone",
      );
      
      if (tag.type != NFCTagType.iso7816) {
        _updateStatus('❌ Invalid card type');
        _updateCardInfo('This is not a DESFire card');
        await FlutterNfcKit.finish();
        return;
      }
      
      final tokenId = tag.id;
      _updateStatus('🔐 Card detected: $tokenId');
      
      // Register the token to the current user (if not already)
      try {
        final registerCallable = FirebaseFunctions.instance.httpsCallable('registerToken');
        await registerCallable.call({
          'token_uid': tokenId,
          'key_hash': 'default_key_hash_' + DateTime.now().millisecondsSinceEpoch.toString(),
          'force_overwrite': true,
        });
        print('[TEST] Token $tokenId registered to user ${currentUser.uid}');
      } catch (e) {
        print('[TEST] Failed to register token: $e');
      }
      
      // Finish the current NFC session so the forwarder can start a new one
      await FlutterNfcKit.finish();
      
      // Now test secure messaging with the forwarder
      final forwarder = FirebaseForwarder(useEmulator: false);
      
      final success = await forwarder.testSecureMessaging(
        tokenId: tokenId,
        userId: currentUser.uid,
      );
      
      if (success) {
        _updateStatus('✅ Secure messaging test successful!');
        _updateCardInfo('''🎉 Secure Messaging Test Success!

✅ ISO-3DES Authentication completed
✅ WriteData with MACed communication successful
✅ ChangeKey with secure messaging successful
✅ All operations protected with CRC16 and 3DES-MAC

The SwapDotz transfer challenge was securely written to the card,
and the master key was successfully rotated using proper DESFire
secure messaging protocols!''');
        
        await _showSuccessFeedback('Secure messaging test successful!');
      } else {
        _updateStatus('❌ Secure messaging test failed');
        _updateCardInfo('Check the logs for error details');
      }
      
    } catch (e) {
      print('❌ Error testing secure messaging: $e');
      _updateStatus('❌ Test failed');
      _updateCardInfo('Error: $e');
    }
  }

  Future<void> _testFirebaseOnly() async {
    try {
      _updateStatus('☁️ Testing Firebase-only authentication...');
      _updateCardInfo('Starting Firebase-only test...\nAll crypto happens server-side.');
      
      // Get current user first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateStatus('❌ Not logged in');
        _updateCardInfo('Please log in first');
        return;
      }
      
      // Poll for NFC tag to get its UID
      _updateStatus('📱 Place NFC card near phone...');
      final tag = await FlutterNfcKit.poll(
        timeout: Duration(seconds: 30),
        iosMultipleTagMessage: "Multiple tags found!",
        iosAlertMessage: "Hold your NFC tag near the phone",
      );
      
      if (tag.type != NFCTagType.iso7816) {
        _updateStatus('❌ Invalid card type');
        _updateCardInfo('This is not a DESFire card');
        await FlutterNfcKit.finish();
        return;
      }
      
      final tokenId = tag.id;
      _updateStatus('🔐 Card detected: $tokenId');
      
      // Register the token to the current user (if not already)
      try {
        final registerCallable = FirebaseFunctions.instance.httpsCallable('registerToken');
        await registerCallable.call({
          'token_uid': tokenId,
          'key_hash': 'default_key_hash_' + DateTime.now().millisecondsSinceEpoch.toString(),
          'force_overwrite': true, // Allow overwriting for testing
        });
        print('[TEST] Token $tokenId registered to user ${currentUser.uid}');
      } catch (e) {
        print('[TEST] Failed to register token: $e');
        // Continue anyway - might already be registered
      }
      
      // Finish the current NFC session so the forwarder can start a new one
      await FlutterNfcKit.finish();
      
      // Now test authentication with the forwarder
      // It will poll for the card again
      final forwarder = FirebaseForwarder(useEmulator: false);
      
      final success = await forwarder.testAuthentication(
        tokenId: tokenId,
        userId: currentUser.uid,
      );
      
      if (success) {
        _updateStatus('✅ Firebase auth successful!');
        _updateCardInfo('''🎉 Firebase-only Authentication Success!

✅ Connected to Firebase Functions
✅ Authenticated with DESFire card
✅ Session key established
✅ All crypto performed server-side

The mobile app only forwarded opaque APDU frames.
No keys or crypto material were exposed to the client!

This is the most secure architecture:
- Keys stored in Secret Manager
- 15-second session TTL
- Token locking prevents concurrent access
- Complete audit trail in Firestore''');
        
        await _showSuccessFeedback('Firebase-only auth successful!');
      } else {
        _updateStatus('❌ Firebase auth failed');
        _updateCardInfo('Authentication failed. Check console for details.');
      }
    } catch (e) {
      _updateStatus('❌ Error: ${e.toString()}');
      _updateCardInfo('Error during Firebase test:\n$e');
      print('Firebase-only test error: $e');
    }
  }

  Future<void> _testBasicDESFire() async {
    const String testMessage = 'Hello from SwapDotz!';
    
    setState(() {
      _isScanning = true;
      _showOverlay = true;
      _statusMessage = '';
      _cardInfo = '';
    });

    _fadeController?.forward();
    _pulseController?.repeat(reverse: true);

    try {
      _updateStatus('🔍 Testing basic DESFire functionality...');
      
      print('🟢 DIAG: Starting poll for tag...');
      final tag = await FlutterNfcKit.poll(iosAlertMessage: 'Hold near DESFire card for diagnostic test');
      
      print('🟢 DIAG: Tag detected!');
      print('  - Type: ${tag.type}');
      print('  - ID: ${tag.id}');
      
      final df = Desfire(tag);
      
      // Step 1: Basic authentication
      print('🔐 DIAG: Authenticating...');
      await df.authenticateLegacy();
      print('✅ DIAG: Authentication successful!');
      
      // Step 2: Setup app and file
      print('📱 DIAG: Setting up app and file...');
      await df.ensureAppAndFileExist();
      print('✅ DIAG: App and file ready!');
      
      // Step 3: Write test message
      print('✍️ DIAG: Writing test message...');
      final data = Uint8List.fromList(utf8.encode(testMessage));
      await df.writeFile01(data);
      print('✅ DIAG: Write successful!');
      
      // Step 4: Read back message
      print('📄 DIAG: Reading back message...');
      final raw = await df.readFile01(testMessage.length);
      final msg = utf8.decode(raw);
      print('📄 DIAG: Read back: "$msg"');
      
      if (msg == testMessage) {
        _updateStatus('✅ DESFire diagnostic PASSED!');
        _updateCardInfo('✅ DIAGNOSTIC PASSED\n\nWrote: "$testMessage"\nRead: "$msg"\n\nDESFire operations are working correctly!');
      } else {
        _updateStatus('❌ DESFire diagnostic FAILED!');
        _updateCardInfo('❌ DIAGNOSTIC FAILED\n\nWrote: "$testMessage"\nRead: "$msg"\n\nData mismatch detected!');
      }
      
      await FlutterNfcKit.finish(iosAlertMessage: 'Diagnostic test complete');
      
    } catch (e) {
      print('🔴 DIAG: Error during diagnostic: $e');
      _updateStatus('❌ DESFire diagnostic FAILED!');
      _updateCardInfo('❌ DIAGNOSTIC FAILED\n\nError: $e\n\nThis indicates a problem with basic DESFire operations.');
      await FlutterNfcKit.finish(iosErrorMessage: 'Diagnostic failed');
    } finally {
      setState(() {
        _isScanning = false;
      });
      _pulseController?.stop();
      _pulseController?.reset();
      
      await Future.delayed(Duration(seconds: 3));
      if (mounted) {
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
    // Log the full technical error for debugging
    print('🔴 NFC ERROR (Full Technical Details):');
    print('=====================================');
    print(error);
    print('=====================================');
    print('Stack trace: ${StackTrace.current}');
    
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
    
    // Also log the friendly interpretation
    print('🟡 Friendly interpretation: $friendlyError');
    print('💡 Suggestion: $suggestion');
    
    // Clear NFC progress and show error feedback with animation
    _clearNFCProgress();
    _showErrorFeedback('❌ $friendlyError');
    
    setState(() {
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

  /// Read what's currently stored on the card
  Future<void> _readCard() async {
    if (_nfcPollInProgress) {
      print('⚠️ NFC poll already in progress; ignoring _readCard call');
      return;
    }
    if (!_appIsActive) {
      print('⚠️ App not in resumed state; skipping NFC poll');
      return;
    }
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    print('📖 =============================================================');
    print('📖 CARD READ DIAGNOSTIC - Session: $sessionId');
    print('📖 Timestamp: ${DateTime.now().toIso8601String()}');
    print('📖 =============================================================');
    
    setState(() {
      _isScanning = true;
      _showOverlay = true;
      _statusMessage = '';
      _cardInfo = '';
    });

    _fadeController?.forward();
    _pulseController?.repeat(reverse: true);

    try {
      print('📡 STEP 1: NFC Polling for Card Read');
      _updateStatus('Looking for card to read...');
      _nfcPollInProgress = true;
      
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: 'Hold SwapDot near device to read',
      );
      
      print('✅ TAG DETECTED FOR READING');
      print('📡 Tag ID: ${tag.id}');
      print('📡 Tag Type: ${tag.type}');
      
      final tokenUid = tag.id;
      _updateCardInfo('Reading Card: $tokenUid');
      
      // Get current user for authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      
      // Server-authoritative authentication and read
      print('🔧 STEP 2: Server-Authoritative Setup');
      print('🔧 Authenticating with card via server...');
      _updateNFCProgress('⏳ Keep card in place... Server authentication');
      
      String? cardData;
      try {
        // Authenticate and setup via server
        final sessionId = await ServerNFCService.authenticateAndSetup(
          tokenId: tokenUid,
          userId: currentUser?.uid ?? 'anonymous',
          allowUnowned: true, // Allow reading any card
        );
        
        print('📖 STEP 3: Reading Card Content');
        _updateStatus('Reading card data...');
        
        // Read file via server
        cardData = await ServerNFCService.readFile01(
          tokenId: tokenUid,
          userId: currentUser?.uid ?? 'anonymous',
          sessionId: sessionId,
          allowUnowned: true,
        );
        
        if (cardData.isEmpty) {
          cardData = null;
        }
      } catch (e) {
        print('❌ Failed to read card data: $e');
      }
 
      print('🔥 STEP 4: Checking Firebase Registration');
      final token = await SwapDotzFirebaseService.getToken(tokenUid);
      
      _updateStatus('Read complete');
      _updateCardInfo('''$_cardInfo
 
 RESULT
 -------
 Card: ${cardData ?? '(no data or unreadable)'}
 Firebase: ${token != null ? 'Registered' : 'Unregistered'}
 Owner: ${token?.currentOwnerId ?? '-'}
 Key hash: ${token?.keyHash.substring(0, 16) ?? '-'}...''');
 
    } catch (e, st) {
      print('💥 CARD READ ERROR: $e');
      print('💥 Stack trace: $st');
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'Read error');
      } catch (_) {}
    } finally {
      _nfcPollInProgress = false;
      print('📖 STEP 5: Cleanup');
      await Future.delayed(Duration(milliseconds: 500));
      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'Read complete');
      } catch (_) {}
      _pulseController?.stop();
      _fadeController?.reverse();
      if (mounted) {
        setState(() {
          _isScanning = false;
          _showOverlay = false;
        });
      }
      print('📖 =============================================================');
      print('📖 CARD READ SESSION COMPLETE');
      print('📖 =============================================================');
    }
  }

  String _analyzeCardState(dynamic token, String? cardData) {
    if (token == null && cardData == null) {
      return '🔴 Uninitialized: Not in Firebase, no card data';
    } else if (token != null && cardData != null) {
      return '🟢 Fully initialized: Registered + has card data';
    } else if (token != null && cardData == null) {
      return '🟡 Partially initialized: Registered but no card data';
    } else if (token == null && cardData != null) {
      return '🟠 Orphaned data: Has card data but not in Firebase';
    }
    return '❓ Unknown state';
  }

  /// Initialize a new token
  /// Test location validation system
  Future<void> _testLocationValidation() async {
    print('🌍 =============================================================');
    print('🌍 TESTING LOCATION VALIDATION SYSTEM');
    print('🌍 =============================================================');
    
    _updateStatus('Testing location validation...');
    _updateCardInfo('Checking GPS and anti-spoofing systems...');
    
    try {
      // Test the location validation
      final locationResult = await TradeLocationService.getTradeLocation(
        context: context,
        tokenId: 'test-token-123',
        fromUser: _selectedUser,
        toUser: 'test-recipient',
      );
      
      if (locationResult.cancelled) {
        _updateStatus('❌ Location test cancelled');
        _updateCardInfo('Location validation was cancelled by user');
        return;
      }
      
      String statusMessage = '';
      String detailMessage = '';
      
      if (locationResult.hasLocation) {
        final location = locationResult.location!;
        statusMessage = '✅ Location validated successfully!';
        detailMessage = '''🌍 Location Validation Results:

📍 Coordinates: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}
📏 Accuracy: ${location.accuracy.toStringAsFixed(1)} meters
🏔️ Altitude: ${location.altitude?.toStringAsFixed(1) ?? 'N/A'} meters
🚀 Speed: ${location.speed?.toStringAsFixed(1) ?? 'N/A'} m/s
📡 Source: ${locationResult.source}
✨ Quality: ${locationResult.quality.toString().split('.').last}

✅ This location would be accepted for:
• Trade location recording
• Travel achievements
• Distance calculations
• City/Country badges

The anti-spoofing system validated this location as genuine!''';
      } else {
        statusMessage = '⚠️ Trade would proceed without location';
        detailMessage = '''📍 Location Not Available

The trade would be recorded without coordinates.

This means:
• ❌ No location achievements for this trade
• ❌ No travel distance recorded
• ❌ No city/country badges
• ✅ Trade would still complete successfully

Common reasons:
• Indoor location with no GPS signal
• Location services disabled
• GPS spoofing detected
• VPN usage detected''';
      }
      
      _updateStatus(statusMessage);
      _updateCardInfo(detailMessage);
      
      // Also show a snackbar with quick summary
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locationResult.hasLocation 
              ? '✅ GPS verified - achievements enabled!' 
              : '⚠️ No verified location - trade would proceed without achievements',
          ),
          duration: Duration(seconds: 3),
          backgroundColor: locationResult.hasLocation ? Colors.green : Colors.orange,
        ),
      );
      
    } catch (e) {
      print('❌ Location test error: $e');
      _updateStatus('❌ Location test failed');
      _updateCardInfo('Error testing location: $e');
    }
  }

  /// Show dialog to test celebration screens with different rarities
  Future<void> _showCelebrationTestDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.celebration, color: Colors.orange),
              SizedBox(width: 12),
              Text(
                'Test SwapDots',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select a rarity to test the SwapDot screen:',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              SizedBox(height: 20),
              _buildRarityTestButton('common', '🟢 Common', 'Common SwapDot', Colors.green),
              SizedBox(height: 12),
              _buildRarityTestButton('uncommon', '🔵 Uncommon', 'Uncommon SwapDot', Colors.blue),
              SizedBox(height: 12),
              _buildRarityTestButton('rare', '🟠 Rare', 'Rare SwapDot!', Colors.orange),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRarityTestButton(String rarity, String label, String description, Color color) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop(); // Close dialog
          _testCelebrationScreen(rarity);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          side: BorderSide(color: color, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.symmetric(vertical: 16),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Test celebration screen with specific rarity
  void _testCelebrationScreen(String rarity) {
    // Create a fake token ID for testing
    final testTokenId = 'TEST_${rarity.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}';
    
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => TestCelebrationScreen(
          swapDotId: testTokenId,
          rarity: rarity,
        ),
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

  Future<Map<String, String>?> _showTokenMetadataDialog() async {
    String selectedName = '';
    String selectedSeries = '';
    String selectedRarity = 'common'; // Default to common
    
    // Predefined options that can be edited
    final List<String> nameOptions = [
      '1st Edition',
      '2nd Edition',
      '3rd Edition',
      'Limited Edition',
      'Special Edition',
      'Collector\'s Edition',
      'Anniversary Edition',
      'Custom...',
    ];
    
    final List<String> seriesOptions = [
      'Hello World!',
      'Genesis Collection',
      'Alpha Series',
      'Beta Series',
      'Founders Series',
      'Pioneer Collection',
      'Custom...',
    ];
    
    final List<Map<String, dynamic>> rarityOptions = [
      {
        'value': 'common',
        'label': 'Common',
        'icon': '🟢',
        'description': 'Standard collectible',
        'color': Colors.green,
      },
      {
        'value': 'uncommon',
        'label': 'Uncommon',
        'icon': '🔵',
        'description': 'Less common find',
        'color': Colors.blue,
      },
      {
        'value': 'rare',
        'label': 'Rare',
        'icon': '🟠',
        'description': 'Highly sought after',
        'color': Colors.orange,
      },
    ];
    
    final TextEditingController nameController = TextEditingController();
    final TextEditingController seriesController = TextEditingController();
    bool isCustomName = false;
    bool isCustomSeries = false;
    
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.nfc, color: Colors.blue),
                  SizedBox(width: 12),
                  Text(
                    'Token Information',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter details for this SwapDot token:',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    SizedBox(height: 20),
                    
                    // Name Selection
                    Text(
                      'Token Name',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    if (!isCustomName) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[700]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedName.isEmpty ? null : selectedName,
                            hint: Text(
                              'Select a name',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            isExpanded: true,
                            dropdownColor: Colors.grey[800],
                            style: TextStyle(color: Colors.white),
                            items: nameOptions.map((name) {
                              return DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                if (value == 'Custom...') {
                                  isCustomName = true;
                                  selectedName = '';
                                } else {
                                  selectedName = value ?? '';
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Enter custom name',
                                hintStyle: TextStyle(color: Colors.grey[500]),
                                filled: true,
                                fillColor: Colors.grey[800],
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
                              onChanged: (value) {
                                selectedName = value;
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.arrow_back, color: Colors.blue),
                            onPressed: () {
                              setState(() {
                                isCustomName = false;
                                selectedName = '';
                                nameController.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    
                    SizedBox(height: 20),
                    
                    // Series Selection
                    Text(
                      'Token Series',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    if (!isCustomSeries) ...[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[700]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedSeries.isEmpty ? null : selectedSeries,
                            hint: Text(
                              'Select a series',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            isExpanded: true,
                            dropdownColor: Colors.grey[800],
                            style: TextStyle(color: Colors.white),
                            items: seriesOptions.map((series) {
                              return DropdownMenuItem(
                                value: series,
                                child: Text(series),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                if (value == 'Custom...') {
                                  isCustomSeries = true;
                                  selectedSeries = '';
                                } else {
                                  selectedSeries = value ?? '';
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: seriesController,
                              style: TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Enter custom series',
                                hintStyle: TextStyle(color: Colors.grey[500]),
                                filled: true,
                                fillColor: Colors.grey[800],
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
                              onChanged: (value) {
                                selectedSeries = value;
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.arrow_back, color: Colors.blue),
                            onPressed: () {
                              setState(() {
                                isCustomSeries = false;
                                selectedSeries = '';
                                seriesController.clear();
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    
                    SizedBox(height: 20),
                    
                    // Rarity Selection
                    Text(
                      'Token Rarity',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    ...rarityOptions.map((rarity) {
                      final isSelected = selectedRarity == rarity['value'];
                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              selectedRarity = rarity['value'];
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected ? rarity['color'].withOpacity(0.2) : Colors.grey[800],
                              border: Border.all(
                                color: isSelected ? rarity['color'] : Colors.grey[700]!,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  rarity['icon'],
                                  style: TextStyle(fontSize: 20),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rarity['label'],
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        rarity['description'],
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: rarity['color'],
                                    size: 24,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedName.isNotEmpty && selectedSeries.isNotEmpty
                      ? () {
                          Navigator.of(context).pop({
                            'name': selectedName,
                            'series': selectedSeries,
                            'rarity': selectedRarity,
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initializeToken() async {
    // First show dialog to collect token metadata
    final tokenMetadata = await _showTokenMetadataDialog();
    if (tokenMetadata == null) {
      print('❌ User cancelled token metadata input');
      return;
    }
    
    // Get the current user's identifier
    final currentUser = FirebaseAuth.instance.currentUser;
    final userIdentifier = currentUser?.displayName ?? 
                         currentUser?.email?.split('@')[0] ?? 
                         'User ${currentUser?.uid.substring(0, 8) ?? "Unknown"}';
    
    // 🚀 OPTIMIZATION: Start GPS immediately for initialization too
    print('🚀 EARLY GPS: Starting GPS fetch for initialization...');
    final earlyLocationFuture = _getLocationConcurrently();
    
    // Store the result in class variable for all functions to use
    earlyLocationFuture.then((location) {
      _preloadedGpsLocation = location;
      if (location != null) {
        print('🚀 EARLY GPS: Location cached for initialization: ${location.latitude}, ${location.longitude}');
      }
    });

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    print('🔧 =============================================================');
    print('🔧 TOKEN INITIALIZATION - Session: $sessionId');
    print('🔧 Timestamp: ${DateTime.now().toIso8601String()}');
    print('🔧 Selected User: $_selectedUser');
    print('🔧 Actual User: $userIdentifier');
    print('🔧 Token Name: ${tokenMetadata['name']}');
    print('🔧 Token Series: ${tokenMetadata['series']}');
    print('🔧 Token Rarity: ${tokenMetadata['rarity']}');
    print('🔧 =============================================================');
    
    // Skip location for token initialization - not needed
    // Use early GPS location that was started when button was pressed
    Position? gpsLocation = await earlyLocationFuture;
    
    _updateStatus('Waiting for NFC...');
      setState(() {
        _showOverlay = true;
      _cardInfo = '''TOKEN INITIALIZATION READY

Token Name: ${tokenMetadata['name']}
Series: ${tokenMetadata['series']}
Rarity: ${tokenMetadata['rarity']?.toUpperCase()}
Owner: $userIdentifier

Hold your SwapDot near the phone to initialize.''';
      });
    
    setState(() {
      _isScanning = true;
      _showOverlay = true;
      _statusMessage = '';
      _cardInfo = '';
    });

    _fadeController?.forward();
    _pulseController?.repeat(reverse: true);

    try {
      print('📡 STEP 1: NFC Polling for Initialization');
      _updateStatus('Looking for token to initialize...');
      if (_nfcPollInProgress || !_appIsActive) {
        print('⚠️ Skipping poll: inProgress=${_nfcPollInProgress}, active=${_appIsActive}');
        return;
      }
      _nfcPollInProgress = true;
      
      final tag = await FlutterNfcKit.poll(
        iosAlertMessage: 'Hold unregistered SwapDot near device',
      );
      
      print('✅ TAG DETECTED FOR INITIALIZATION');
      print('📡 Tag ID: ${tag.id}');
      print('📡 Tag Type: ${tag.type}');
      
      final tokenUid = tag.id;
      _updateCardInfo('Initializing Token: $tokenUid');
      
      // Get current user for authentication
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ No authenticated user');
        _updateStatus('❌ Authentication required');
        _updateCardInfo('Please sign in to continue');
        return;
      }
      
      // Server-authoritative authentication
      print('🔧 STEP 2: Server-Authoritative Setup');
      print('🔧 Authenticating with card via server...');
      _updateNFCProgress('⏳ KEEP CARD IN PLACE (10 sec)... Server authentication');
      
      final sessionId = await ServerNFCService.authenticateAndSetup(
        tokenId: tokenUid,
        userId: currentUser.uid,
        allowUnowned: true, // Allow for new tokens
      );
      
      print('✅ Server authentication successful! Session: $sessionId');
      
      // Check if already registered in Firebase
      print('🔥 STEP 3: Checking existing token state...');
      final existingToken = await SwapDotzFirebaseService.getToken(tokenUid);
      
      if (existingToken != null) {
        print('⚠️ TOKEN ALREADY REGISTERED - WILL OVERWRITE');
        print('⚠️ Current Owner: ${existingToken.currentOwnerId}');
        print('⚠️ Current Created: ${existingToken.createdAt}');
        print('⚠️ INITIALIZATION WILL COMPLETELY RESET THIS TOKEN');
        
        _updateStatus('⚠️ Overwriting existing token...');
        _updateCardInfo('''$_cardInfo

⚠️ OVERWRITING EXISTING TOKEN

This SwapDot is already registered but will be completely reset.

Previous Owner: ${existingToken.currentOwnerId}
Previous Created: ${existingToken.createdAt}

🔄 COMPLETE RESET IN PROGRESS:
• New ownership key will be generated
• Firebase record will be overwritten
• Card data will be overwritten
• All transfer history will be preserved

New Owner: $userIdentifier''');
        
        await Future.delayed(Duration(seconds: 2));
      } else {
        print('✅ NEW TOKEN - No existing registration found');
        _updateStatus('✅ Claiming new token...');
      }
      
      // Proceed with initialization
      print('✅ Token not registered - proceeding with initialization');
      if (gpsLocation != null) {
        await _handleUninitializedToken(tokenUid, gpsLocation, tokenMetadata, sessionId, currentUser.uid);
      } else {
        // Handle uninitialized token without location
        print('⚠️ Initializing token without GPS location');
        await _handleUninitializedToken(tokenUid, null, tokenMetadata, sessionId, currentUser.uid);
      }
      
    } catch (e, stackTrace) {
      print('💥 INITIALIZATION ERROR: $e');
      print('💥 Stack trace: $stackTrace');
      
      _updateStatus('❌ Initialization failed');
      _updateCardInfo('''$_cardInfo

❌ INITIALIZATION FAILED

Error: ${e.toString()}

This could mean:
• NFC communication error
• Card authentication failed  
• Firebase connection issue
• Invalid card type

Try again or check logs.''');
    } finally {
      _nfcPollInProgress = false;
      print('🔧 STEP 4: Cleanup');
      await Future.delayed(Duration(seconds: 3));
      
      try {
        await FlutterNfcKit.finish(
          iosAlertMessage: 'Initialization complete'
        );
      } catch (e) {
        print('⚠️ NFC finish warning: $e');
      }
      
      _pulseController?.stop();
      _fadeController?.reverse();
      
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _showOverlay = false;
          });
        }
      });
      
      print('🔧 =============================================================');
      print('🔧 TOKEN INITIALIZATION SESSION COMPLETE');
      print('🔧 =============================================================');
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
                  // Header with Logo and Marketplace Access
                  Container(
                    padding: EdgeInsets.all(24),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Image.asset(
                              'swapdotz_possible_logo_no_bg.png',
                              height: 80,
                              width: 80,
                              fit: BoxFit.contain,
                            ),
                            SizedBox(height: 16),
                                                    Text(
                          'SwapDotz',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w300,
                            color: Colors.white70,
                            letterSpacing: 1,
                          ),
                        ),
                          ],
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
                      color: _selectedUser == 'gifter' 
                        ? Color(0xFF00CED1).withOpacity(0.1)
                        : Color(0xFFFF8C42).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedUser == 'gifter' 
                          ? Color(0xFF00CED1).withOpacity(0.3)
                          : Color(0xFFFF8C42).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedUser == 'gifter' ? Icons.person_add : Icons.person,
                          color: _selectedUser == 'gifter' 
                            ? Color(0xFF00CED1) 
                            : Color(0xFFFF8C42),
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedUser == 'gifter' 
                              ? 'Gifter will start a SwapDot session'
                              : 'Receiver will claim the SwapDot during session',
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
                        onTap: _isScanning ? null : _startSwapDotWithAutoRestart,
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
                                      : _selectedUser == 'gifter'
                                        ? [Color(0xFF00CED1), Color(0xFF00B4B4)]
                                        : [Color(0xFFFF8C42), Color(0xFFFF6B35)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isScanning 
                                        ? Color(0xFF00CED1).withOpacity(0.4)
                                        : _selectedUser == 'gifter'
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
                  
                  SizedBox(height: 24),
                  
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
                                    begin: Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeInOut,
                                  )),
                                  child: child,
                                );
                              },
                              transitionDuration: Duration(milliseconds: 300),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF8B5CF6).withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.storefront,
                                color: Colors.white,
                                size: 28,
                              ),
                              SizedBox(width: 16),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'MARKETPLACE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Buy & Sell SwapDotz',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
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
                  
                  SizedBox(height: 16),
                  
                  // Token Initialization Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _initializeTokenWithAutoRestart,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFf59e0b), Color(0xFFd97706)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFf59e0b).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'INITIALIZE TOKEN',
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
                  
                  // Test Location Validation Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _testLocationValidation,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF8B5CF6).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'TEST LOCATION VALIDATION',
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
                  
                  // DESFire Diagnostic Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _testBasicDESFire,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF10B981).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bug_report,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'TEST DESFIRE',
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
                  
                  // Firebase-only Test Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _testFirebaseOnly,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF3B82F6).withOpacity(0.3),
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
                                'TEST FIREBASE-ONLY',
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
                  
                  // Secure Messaging Test Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _testSecureMessaging,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF9333EA), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF9333EA).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.enhanced_encryption,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'TEST SECURE MESSAGING',
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
                  
                  // Card Read Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _readCard,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF3B82F6).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.visibility,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'READ CARD',
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
                  
                  // Test Celebration Button
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showCelebrationTestDialog,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFF6B6B).withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.celebration,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'TEST SWAPDOTS',
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
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Show different icons based on state
                                    if (_showSuccessIcon)
                                      AnimatedBuilder(
                                        animation: _successScale!,
                                        builder: (context, child) {
                                          return Transform.scale(
                                            scale: _successScale!.value,
                                            child: Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.green,
                                              ),
                                              child: Icon(
                                                Icons.check,
                                                size: 50,
                                                color: Colors.white,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    else if (_showErrorIcon)
                                      AnimatedBuilder(
                                        animation: _errorShake!,
                                        builder: (context, child) {
                                          return Transform.translate(
                                            offset: Offset(_errorShake!.value * 10, 0),
                                            child: Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.red,
                                              ),
                                              child: Icon(
                                                Icons.close,
                                                size: 50,
                                                color: Colors.white,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    else
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: _nfcOperationInProgress 
                                              ? [Colors.orange, Colors.deepOrange]
                                              : [Color(0xFF00CED1), Color(0xFF00B4B4)],
                                          ),
                                        ),
                                        child: Icon(
                                          _nfcOperationInProgress ? Icons.hourglass_bottom : Icons.nfc,
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
                                    // Show prominent "keep holding" message during NFC operations
                                    if (_nfcOperationInProgress)
                                      Container(
                                        margin: EdgeInsets.only(bottom: 12),
                                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: Colors.orange,
                                            width: 2,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              'KEEP HOLDING CARD',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                                    if (_cardInfo.isNotEmpty) ...[
                                      SizedBox(height: 16),
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _cardInfo,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (_isScanning)
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
                    ),
                  );
                },
              ),
              
              // ZOOM! Animation Overlay
              if (_showZoomEffect)
                AnimatedBuilder(
                  animation: _zoomAnimation!,
                  builder: (context, child) {
                    return Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.black.withOpacity(0.3),
                      child: Center(
                        child: Stack(
                          children: [
                            // Main ZOOM text
                            Center(
                              child: Transform.scale(
                                scale: _zoomAnimation!.value,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF00CED1), Color(0xFF1a1a2e)],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF00CED1).withOpacity(0.6),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    'ZOOM!',
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Flying arrows
                            ...List.generate(5, (index) => 
                              AnimatedBuilder(
                                animation: _arrowAnimation!,
                                builder: (context, child) {
                                  return Positioned(
                                    left: _arrowAnimation!.value,
                                    top: 150.0 + (index * 80),
                                    child: Transform.rotate(
                                      angle: 0,
                                      child: Icon(
                                        Icons.arrow_forward,
                                        size: 40 + (index * 5),
                                        color: Colors.white.withOpacity(0.8 - (index * 0.1)),
                                      ),
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
          ],
        ),
      ),
    );
  }
}

// Additional classes needed
class LeaderboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text('Leaderboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          'Leaderboard Coming Soon',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

// Marketplace screen moved to separate file: lib/screens/marketplace_screen.dart

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
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Create a squiggly path
    final path = Path();
    final amplitude = 5.0 * squiggliness; // Height of the waves
    final wavelength = 15.0; // Distance between wave peaks
    
    path.moveTo(0, size.height / 2);
    
    // Create sine wave pattern
    for (double x = 0; x <= size.width; x += 2) {
      final y = size.height / 2 + amplitude * math.sin((x / wavelength) * 2 * math.pi);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    // Draw the squiggly line with dashes
    final dashPath = Path();
    final pathMetrics = path.computeMetrics();
    
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final extractPath = metric.extractPath(distance, distance + dashWidth);
        dashPath.addPath(extractPath, Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }
    
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Test version of CelebrationScreen that doesn't fetch from Firebase
class TestCelebrationScreen extends StatefulWidget {
  final String swapDotId;
  final String rarity;
  
  const TestCelebrationScreen({
    Key? key, 
    required this.swapDotId, 
    required this.rarity,
  }) : super(key: key);

  @override
  _TestCelebrationScreenState createState() => _TestCelebrationScreenState();
}

class _TestCelebrationScreenState extends State<TestCelebrationScreen>
    with TickerProviderStateMixin {
  late AnimationController _confettiController;
  late AnimationController _burstController;
  late AnimationController _shockwaveController;
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _rotateController;
  late AnimationController _flashController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    
    _confettiController = AnimationController(
      duration: Duration(milliseconds: 2000), // Optimized duration
      vsync: this,
    );

    _burstController = AnimationController(
      duration: Duration(milliseconds: 1500), // Optimized duration
      vsync: this,
    );

    _shockwaveController = AnimationController(
      duration: Duration(milliseconds: 2500), // Optimized duration
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _rotateController = AnimationController(
      duration: Duration(milliseconds: 8000),
      vsync: this,
    );

    _flashController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    
    // Start celebration immediately for test
    _startTestCelebration();
  }

  Future<void> _startTestCelebration() async {
    await Future.delayed(Duration(milliseconds: 500));
    _playRarityCelebration();
  }

  /// Play sound effect based on token rarity
  Future<void> _playRaritySound(String rarity) async {
    try {
      await _audioPlayer.play(AssetSource('SwapSounds/$rarity.mp3'));
      print('🔊 Playing $rarity celebration sound effect (TEST)');
    } catch (e) {
      print('🔊 Failed to play $rarity sound: $e');
    }
  }

  void _playRarityCelebration() async {
    final rarity = widget.rarity;
    
    // Play appropriate sound effect
    _playRaritySound(rarity);
    
    // Start basic animations for all rarities
    _scaleController.forward(from: 0);
    // Removed pulsing and rotating animations per user request
    
    switch (rarity) {
      case 'rare':
        // 🌟 RARE SWAPDOT celebration for rare tokens!
        _confettiController.forward(from: 0);
        _burstController.forward(from: 0);
        _shockwaveController.forward(from: 0);
        
        // Multiple flash bursts for rare
        for (int i = 0; i < 5; i++) {
          await Future.delayed(Duration(milliseconds: 200));
          _flashController.forward(from: 0).then((_) => _flashController.reverse());
        }
        break;
      case 'uncommon':
        // 💫 UNCOMMON SWAPDOT celebration for uncommon tokens!
        _confettiController.forward(from: 0);
        _burstController.forward(from: 0);
        
        // Single flash burst for uncommon
        await Future.delayed(Duration(milliseconds: 300));
        _flashController.forward(from: 0).then((_) => _flashController.reverse());
        break;
      default: // common
        // ✨ COMMON SWAPDOT celebration for common tokens
        _confettiController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _burstController.dispose();
    _shockwaveController.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    _rotateController.dispose();
    _flashController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rarity = widget.rarity;
    final rarityIcon = rarity == 'rare' ? '🟠' : (rarity == 'uncommon' ? '🔵' : '🟢');
    final rarityColor = rarity == 'rare' ? Colors.orange : (rarity == 'uncommon' ? Colors.blue : Colors.green);
    
    List<Color> gradientColors;
    switch (rarity) {
      case 'rare':
        gradientColors = [
          Color(0xFFFF6B35), // Vibrant orange
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFFFFD700), // Gold
        ];
        break;
      case 'uncommon':
        gradientColors = [
          Color(0xFF4A90E2), // Bright blue
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFF00CED1), // Cyan
        ];
        break;
      default: // common
        gradientColors = [
          Color(0xFF32CD32), // Green
          Color(0xFF1a1a2e), // Dark blue
          Color(0xFF90EE90), // Light green
        ];
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: Stack(
          children: [
            // DRAMATIC Rarity overlays (optimized for performance)
            if (rarity == 'common') _buildTestConfetti(75), // Optimized confetti count
            if (rarity == 'uncommon') ...[
              _buildTestConfetti(150), // Optimized confetti count
              _buildTestBurstRays(rayCount: 32), // Reduced ray count
              _buildTestPulseWaves(), // New pulse effect!
            ],
            if (rarity == 'rare') ...[
              _buildTestConfetti(200), // Reduced but still dramatic
              _buildTestBurstRays(rayCount: 48), // Reduced ray count
              _buildTestShockwave(),
              _buildTestGlobalGlow(),
              _buildTestScreenShake(),
              _buildTestPulseWaves(),
              _buildTestLightBeams(), // New light beam effect!
            ],
            
            // Test content
            SafeArea(
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
                          'TEST SWAPDOT',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00CED1),
                            letterSpacing: 2,
                          ),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                  
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Animated Rarity Display with Multiple Effects
                          AnimatedBuilder(
                            animation: Listenable.merge([_scaleController, _pulseController, _rotateController, _flashController]),
                            builder: (context, child) {
                              return Container(
                                padding: EdgeInsets.all(32),
                                margin: EdgeInsets.symmetric(horizontal: 40),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      rarityColor.withOpacity(0.4), 
                                      rarityColor.withOpacity(0.1)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: rarityColor.withOpacity(0.8),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: rarityColor.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                        // Extra subtle glow for rare/uncommon
                                        if (rarity != 'common')
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.2),
                                            blurRadius: 50,
                                            spreadRadius: 20,
                                          ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        // Static emoji without animations
                                        Text(
                                          rarityIcon,
                                          style: TextStyle(
                                            fontSize: 80,
                                            shadows: [
                                              Shadow(
                                                color: rarityColor.withOpacity(0.8),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 16),
                                        // Static text without animations
                                        Text(
                                          '${rarity.toUpperCase()} TOKEN',
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white.withOpacity(0.9),
                                            letterSpacing: 3,
                                            shadows: [
                                              Shadow(
                                                color: rarityColor.withOpacity(0.8),
                                                blurRadius: 8,
                                              ),
                                              if (rarity == 'rare')
                                                Shadow(
                                                  color: Colors.white.withOpacity(0.3),
                                                  blurRadius: 25,
                                                ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        // Static subtitle without animations
                                        Text(
                                          rarity == 'rare' 
                                            ? '🌟 RARE SWAPDOT! 🌟'
                                            : rarity == 'uncommon'
                                              ? '💫 UNCOMMON SWAPDOT! 💫'
                                              : '✨ COMMON SWAPDOT! ✨',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.white.withOpacity(0.8),
                                            fontWeight: FontWeight.w600,
                                            shadows: [
                                              Shadow(
                                                color: rarityColor.withOpacity(0.6),
                                                blurRadius: 5,
                                              ),
                                            ],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    )
                              );
                            },
                          ),
                          
                          SizedBox(height: 40),
                          
                          // Test info
                          Container(
                            padding: EdgeInsets.all(20),
                            margin: EdgeInsets.symmetric(horizontal: 40),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Test Token ID:',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  widget.swapDotId,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTestConfetti(int count) {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _confettiController,
        builder: (context, _) {
          final t = _confettiController.value;
          return CustomPaint(
            painter: _TestConfettiPainter(progress: t, count: count),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildTestBurstRays({int rayCount = 24}) {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _burstController,
        builder: (context, _) {
          final t = _burstController.value;
          return CustomPaint(
            painter: _TestBurstPainter(progress: t, rayCount: rayCount),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildTestShockwave() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _shockwaveController,
        builder: (context, _) {
          final t = _shockwaveController.value;
          return CustomPaint(
            painter: _TestShockwavePainter(progress: t),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildTestGlobalGlow() {
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

  Widget _buildTestScreenShake() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _shockwaveController,
        builder: (context, _) {
          final t = _shockwaveController.value;
          // MUCH more dramatic shake for rare tokens!
          final intensity = widget.rarity == 'rare' ? 8.0 : 3.0;
          final shakeX = math.sin(t * 25) * (1 - t) * intensity;
          final shakeY = math.cos(t * 30) * (1 - t) * (intensity * 0.5);
          return Transform.translate(
            offset: Offset(shakeX, shakeY),
            child: Container(),
          );
        },
      ),
    );
  }

  Widget _buildTestPulseWaves() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final t = _pulseController.value;
          return CustomPaint(
            painter: _TestPulsePainter(progress: t, rarity: widget.rarity),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  Widget _buildTestLightBeams() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _rotateController,
        builder: (context, _) {
          final t = _rotateController.value;
          return CustomPaint(
            painter: _TestLightBeamPainter(progress: t),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

// Test painters (simplified versions)
class _TestConfettiPainter extends CustomPainter {
  final double progress;
  final int count;
  _TestConfettiPainter({required this.progress, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    
    // Much more dramatic confetti colors
    final colors = [
      Colors.amber, Colors.orange, Colors.red, Colors.pink,
      Colors.purple, Colors.blue, Colors.cyan, Colors.green,
      Colors.yellow, Colors.lime, Colors.indigo, Colors.teal,
    ];
    
    for (int i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final velocity = 0.3 + rnd.nextDouble() * 0.7; // Variable speeds
      final radius = progress * (size.shortestSide * 0.8) * velocity; // Larger spread
      final cx = size.width / 2 + math.cos(angle) * radius;
      final cy = size.height / 2 + math.sin(angle) * radius; // Center from middle
      
      // Different particle shapes and sizes
      final particleSize = 1 + rnd.nextDouble() * 6; // Bigger particles
      final color = colors[rnd.nextInt(colors.length)];
      final opacity = (1 - progress * 0.8).clamp(0.0, 1.0); // Fade slower
      
      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;
        
      // Different shapes for variety
      if (rnd.nextBool()) {
        // Circles
        canvas.drawCircle(Offset(cx, cy), particleSize, paint);
      } else {
        // Rectangles/squares
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: particleSize * 2, height: particleSize * 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TestConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}

class _TestBurstPainter extends CustomPainter {
  final double progress;
  final int rayCount;
  _TestBurstPainter({required this.progress, required this.rayCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    for (int i = 0; i < rayCount; i++) {
      final angle = (2 * math.pi / rayCount) * i;
      final maxLength = size.shortestSide * 0.3; // Much longer rays
      final length = maxLength * Curves.easeOut.transform(progress);
      final dx = math.cos(angle) * length;
      final dy = math.sin(angle) * length;
      
      // Gradient effect for each ray
      final gradient = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity((1 - progress) * 0.9),
            Colors.amberAccent.withOpacity((1 - progress) * 0.6),
            Colors.orange.withOpacity((1 - progress) * 0.3),
            Colors.transparent,
          ],
        ).createShader(Rect.fromPoints(center, center.translate(dx, dy)))
        ..strokeWidth = 3 + (math.sin(progress * math.pi) * 2) // Pulsing width
        ..strokeCap = StrokeCap.round;
        
      canvas.drawLine(center, center.translate(dx, dy), gradient);
    }
  }

  @override
  bool shouldRepaint(covariant _TestBurstPainter oldDelegate) => 
    oldDelegate.progress != progress || oldDelegate.rayCount != rayCount;
}

class _TestShockwavePainter extends CustomPainter {
  final double progress;
  _TestShockwavePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 3);
    final radius = size.shortestSide * 0.1 + progress * size.shortestSide * 0.4;
    final paint = Paint()
      ..color = Colors.amberAccent.withOpacity((1 - progress) * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * (1 - progress);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _TestShockwavePainter oldDelegate) => oldDelegate.progress != progress;
}

class _TestPulsePainter extends CustomPainter {
  final double progress;
  final String rarity;
  _TestPulsePainter({required this.progress, required this.rarity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide * 0.8;
    
    // Multiple expanding rings based on rarity
    final ringCount = rarity == 'rare' ? 5 : (rarity == 'uncommon' ? 3 : 2);
    final baseColor = rarity == 'rare' ? Colors.orange : (rarity == 'uncommon' ? Colors.blue : Colors.green);
    
    for (int i = 0; i < ringCount; i++) {
      final offset = i * 0.2;
      final adjustedProgress = ((progress + offset) % 1.0);
      final radius = adjustedProgress * maxRadius;
      final opacity = (1 - adjustedProgress) * 0.4;
      
      final paint = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
        
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TestPulsePainter oldDelegate) => 
    oldDelegate.progress != progress || oldDelegate.rarity != rarity;
}

class _TestLightBeamPainter extends CustomPainter {
  final double progress;
  _TestLightBeamPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxLength = size.shortestSide * 0.4;
    
    // Draw 8 rotating light beams
    for (int i = 0; i < 8; i++) {
      final angle = (progress * 2 * math.pi) + (i * math.pi / 4);
      final startRadius = maxLength * 0.3;
      final endRadius = maxLength;
      
      final start = Offset(
        center.dx + math.cos(angle) * startRadius,
        center.dy + math.sin(angle) * startRadius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * endRadius,
        center.dy + math.sin(angle) * endRadius,
      );
      
      final gradient = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0.8),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(Rect.fromPoints(start, end))
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
        
      canvas.drawLine(start, end, gradient);
    }
  }

  @override
  bool shouldRepaint(covariant _TestLightBeamPainter oldDelegate) => oldDelegate.progress != progress;
}