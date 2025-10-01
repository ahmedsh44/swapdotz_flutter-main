# NFC Debug Logging Guide

## Overview
Comprehensive debug logging has been added to the SwapDotz app to help diagnose NFC communication issues. The logging uses color-coded emojis for quick visual identification of log types.

## Log Types

### 🟢 Success Operations
- Tag detection with full details (type, ID, standard, ATQ, SAK)
- Authentication success
- File structure setup
- Successful reads with raw bytes and decoded data
- Successful writes with data and byte lengths
- Scenario completion

### 🔵 Scenario Identification
- Clearly identifies which of the 5 scenarios is being executed:
  1. Uninitialized token claiming
  2. Owner starting transfer (with sub-cases for server commands)
  3. Recipient claiming token
  4. Not your token (no transfer)
  5. Transfer already in progress

### 🟡 Warnings
- File read failures (usually means uninitialized)
- Non-critical issues that don't stop the flow

### 🔴 Errors
- DESFire-specific errors with full details
- General NFC errors with stack traces
- Timestamp of when error occurred
- Error type (runtimeType)
- Full error message
- Friendly interpretation for users

## What Gets Logged

### On Every NFC Scan:
1. **Tag Detection**
   ```
   🟢 NFC: Tag detected!
     - Type: com.nxp.mifare.desfire.ev1
     - ID: 04:12:34:56:78:90:AB
     - Standard: 14443-4A
     - ATQ: 0344
     - SAK: 20
   ```

2. **Authentication**
   ```
   🟢 NFC: Attempting DES authentication...
   🟢 NFC: Authentication successful!
   ```

3. **File Operations**
   ```
   🟢 NFC: Reading file 01...
   🟢 NFC: File data read successfully
     - Raw bytes: [111, 119, 110, 101, 114, 58, ...] ...
     - Decoded: owner:oliver;key:a1b2c3...;initialized:1234567890
   ```

4. **Data Parsing**
   ```
   🟢 NFC: Parsed data:
     - Owner: oliver
     - Has key: true
     - Transfer active: false
   ```

5. **Write Operations**
   ```
   🟢 NFC: Writing initial ownership data...
     - Data to write: owner:jonathan;key:f4e5d6...;initialized:1234567890
     - Bytes length: 87
   🟢 NFC: Write successful! Token claimed by jonathan
   ```

### On Errors:
```
🔴 DESFire-specific error caught:
Type: DESFireError
Message: Card returned: 91 ae
Time: 2024-01-15T10:30:45.123Z

🔴 NFC ERROR (Full Technical Details):
=====================================
Card returned: 91 ae
=====================================
Stack trace: [full stack trace]

🟡 Friendly interpretation: Authentication failed
💡 Suggestion: This SwapDot uses a different key.
```

## How to Use

### During Development:
1. Run the app with `flutter run`
2. Watch the console output
3. Look for the color-coded emojis to quickly identify issues

### For iOS:
- Open Xcode and view the console
- Or use `flutter logs` in terminal

### For Android:
- Use Android Studio's Logcat
- Or watch the `flutter run` console output

### Debugging Tips:
1. **Authentication failures** (91 ae): Check if the token uses a different key
2. **File not found** (91 f0): Token needs initialization
3. **Permission denied** (91 9d): Token is locked or uses different permissions
4. **Tag lost**: User moved the token too quickly

## Production Considerations
Remember to remove or reduce logging verbosity for production builds to:
- Improve performance
- Protect sensitive data (like keys)
- Reduce console noise

Consider using a logging package like `logger` with different log levels for dev/prod. 