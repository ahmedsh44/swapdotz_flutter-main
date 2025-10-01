/// NXP MIFARE DESFire EV2/EV3 Full Specifications
class NXPAESConstants {
  // Command set for EV2/EV3
  static const int AUTHENTICATE_AES = 0xAA;
  static const int AUTHENTICATE_AES_EV2 = 0x71;
  static const int READ_DATA = 0xBD;
  static const int WRITE_DATA = 0x3D;
  static const int READ_VALUE = 0x6C;
  static const int CREDIT = 0x0C;
  static const int DEBIT = 0xDC;
  static const int LIMITED_CREDIT = 0x1C;
  static const int WRITE_RECORD = 0x3B;
  static const int READ_RECORDS = 0xBB;
  static const int CLEAR_RECORD_FILE = 0xEB;
  static const int COMMIT_TRANSACTION = 0xC7;
  static const int ABORT_TRANSACTION = 0xA7;
  
  // Security parameters
  static const int AES128_KEY_LENGTH = 16;
  static const int CMAC_LENGTH = 8; // 64-bit CMAC
  static const int CRYPTOGRAM_LENGTH = 16;
  static const int MAX_FRAME_SIZE = 60;
  
  // Secure messaging modes
  static const int PLAIN = 0x00;        // No encryption, no CMAC
  static const int MACED = 0x01;        // CMAC only
  static const int FULL_ENCRYPTION = 0x03; // Encryption + CMAC
  
  // Status codes
  static const int OPERATION_OK = 0x00;
  static const int ADDITIONAL_FRAME = 0xAF;
  static const int PERMISSION_DENIED = 0x9D;
  static const int AUTHENTICATION_ERROR = 0xAE;
}