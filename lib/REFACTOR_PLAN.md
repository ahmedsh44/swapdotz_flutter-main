# Flutter App Refactoring Plan

## Current Issues
- `main.dart` is 3,486 lines with multiple screens and classes
- No separation of concerns
- Business logic mixed with UI
- No proper folder structure
- Difficult to maintain and test

## Proposed Structure

```
lib/
├── main.dart                    # App entry point only (~50 lines)
├── app.dart                     # MyApp widget
│
├── screens/
│   ├── splash_screen.dart       # SplashScreen widget
│   ├── home_screen.dart         # SwapDotzApp main screen
│   ├── celebration_screen.dart  # CelebrationScreen
│   ├── version_check_screen.dart # ✓ Already separate
│   ├── firebase_demo_screen.dart # ✓ Already separate
│   └── error_screen.dart        # Error display screen
│
├── widgets/
│   ├── swap_button.dart         # Main swap button widget
│   ├── user_selector.dart      # Oliver/Jonathan selector
│   ├── nfc_overlay.dart        # NFC scanning overlay
│   ├── leaderboard_widget.dart # Leaderboard display
│   └── animated_logo.dart      # Reusable logo animations
│
├── services/
│   ├── nfc_service.dart        # NFC operations logic
│   ├── firebase_service.dart   # Firebase integration
│   ├── version_service.dart    # Version checking logic
│   └── key_manager.dart        # Key generation/management
│
├── models/
│   ├── transfer_session.dart   # Transfer session model
│   ├── token_data.dart         # Token data model
│   ├── user_model.dart         # User model
│   └── leaderboard_entry.dart  # Leaderboard entry model
│
├── utils/
│   ├── constants.dart          # App constants
│   ├── theme.dart              # App theme/colors
│   ├── validators.dart         # Input validators
│   └── helpers.dart            # Helper functions
│
└── controllers/
    ├── nfc_controller.dart     # NFC business logic
    ├── transfer_controller.dart # Transfer flow logic
    └── auth_controller.dart    # Authentication logic
```

## Refactoring Steps

### Phase 1: Extract Screens (Priority: High)
1. Move `CelebrationScreen` to `screens/celebration_screen.dart`
2. Move `SplashScreen` to `screens/splash_screen.dart`
3. Move `SwapDotzApp` to `screens/home_screen.dart`
4. Create `app.dart` for `MyApp` widget

### Phase 2: Extract Services (Priority: High)
1. Create `services/nfc_service.dart`:
   - Move `_startSwapDot()` logic
   - Move `_executeServerCommand()` logic
   - Move NFC-related methods
   
2. Create `services/key_manager.dart`:
   - Move key generation logic
   - Move `_hexToBytes()` helper
   - Add key validation methods

### Phase 3: Extract Widgets (Priority: Medium)
1. Extract the main swap button to `widgets/swap_button.dart`
2. Extract user selector to `widgets/user_selector.dart`
3. Extract NFC overlay to `widgets/nfc_overlay.dart`
4. Extract leaderboard to `widgets/leaderboard_widget.dart`

### Phase 4: Create Models (Priority: Medium)
1. Define data models for type safety
2. Replace Map<String, dynamic> with proper models
3. Add serialization/deserialization methods

### Phase 5: Add State Management (Priority: Low)
1. Consider adding Provider or Riverpod
2. Separate UI state from business logic
3. Make the app more testable

## Benefits

1. **Maintainability**: Easy to find and modify specific features
2. **Testability**: Can unit test services independently
3. **Scalability**: Easy to add new features
4. **Team Collaboration**: Multiple developers can work on different parts
5. **Code Reusability**: Widgets and services can be reused
6. **Performance**: Smaller files compile faster

## Example Refactored Code

### `lib/main.dart` (After Refactor)
```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}
```

### `lib/services/nfc_service.dart`
```dart
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../models/token_data.dart';
import '../utils/key_manager.dart';

class NFCService {
  static Future<TokenData> readToken() async {
    final tag = await FlutterNfcKit.poll();
    // ... NFC logic
  }
  
  static Future<void> writeToken(TokenData data) async {
    // ... Write logic
  }
}
```

## Testing Strategy

After refactoring, add tests:
1. Unit tests for services
2. Widget tests for UI components
3. Integration tests for full flows
4. Golden tests for screens

## Migration Plan

1. **Create new structure** without breaking existing code
2. **Move code gradually** to new files
3. **Update imports** as you go
4. **Test each step** to ensure nothing breaks
5. **Delete old code** only after new code works

## Time Estimate

- Phase 1: 2-3 hours
- Phase 2: 3-4 hours  
- Phase 3: 2-3 hours
- Phase 4: 2 hours
- Phase 5: 4-6 hours (optional)

**Total: 13-18 hours for complete refactor**

## Quick Wins (1-2 hours)

If you want immediate improvements:
1. Extract `CelebrationScreen` to its own file
2. Extract NFC logic to `services/nfc_service.dart`
3. Create `utils/constants.dart` for magic strings
4. Move server commands to `services/server_commands.dart` 