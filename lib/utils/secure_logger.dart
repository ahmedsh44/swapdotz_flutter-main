class SecureLogger {
  static bool isDebugMode = false;
  
  static void enableDebugMode(bool enable) {
    isDebugMode = enable;
  }
  
  static void info(String message) {
    print('INFO: $message');
  }
  
  static void debug(String message) {
    if (isDebugMode) {
      print('DEBUG: $message');
    }
  }
  
  static void warning(String message) {
    print('WARNING: $message');
  }
  
  static void error(String message) {
    print('ERROR: $message');
  }
  
  static void setDebugMode(bool enabled) {
    isDebugMode = enabled;
  }
}