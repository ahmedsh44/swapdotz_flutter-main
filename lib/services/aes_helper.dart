import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/block/aes_fast.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'nxp_aes_constants.dart';

class AESHelper {
  // PROPER AES-CMAC implementation (NIST SP 800-38B)
  static Uint8List calculateAESCMAC(Uint8List data, Uint8List key) {
    final cipher = AESFastEngine();
    cipher.init(true, KeyParameter(key));
    
    // Generate subkeys
    final k1 = _generateSubkey(cipher, Uint8List(16));
    final k2 = _generateSubkey(cipher, k1);
    
    // Process blocks
    var result = Uint8List(16);
    final blocks = _splitIntoBlocks(data);
    
    for (int i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      
      if (i == blocks.length - 1) {
        // Last block
        if (block.length == 16) {
          block = _xor(block, k1);
        } else {
          block = _padBlock(block);
          block = _xor(block, k2);
        }
      }
      
      result = _xor(result, block);
      result = cipher.process(result);
    }
    
    return Uint8List.fromList(result.sublist(0, 8)); // 8-byte CMAC
  }
  
  static Uint8List _generateSubkey(BlockCipher cipher, Uint8List input) {
    var l = cipher.process(input);
    
    // Left shift and conditional XOR
    final carry = (l[0] & 0x80) != 0;
    for (int i = 0; i < 15; i++) {
      l[i] = ((l[i] << 1) | (l[i + 1] >> 7)) & 0xFF;
    }
    l[15] = (l[15] << 1) & 0xFF;
    
    if (carry) {
      l[15] ^= 0x87; // Rb constant for 128-bit AES
    }
    
    return l;
  }
  
  static List<Uint8List> _splitIntoBlocks(Uint8List data) {
    final blocks = <Uint8List>[];
    for (int i = 0; i < data.length; i += 16) {
      final end = (i + 16 <= data.length) ? i + 16 : data.length;
      blocks.add(Uint8List.fromList(data.sublist(i, end)));
    }
    return blocks;
  }
  
  static Uint8List _xor(Uint8List a, Uint8List b) {
    final result = Uint8List(a.length);
    for (int i = 0; i < a.length; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }
  
  static Uint8List _padBlock(Uint8List block) {
    final padded = Uint8List(16)..setRange(0, block.length, block);
    padded[block.length] = 0x80; // Padding start
    return padded;
  }

  // Rest of AES methods remain similar but with proper CMAC integration
}