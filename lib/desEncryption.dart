// Copyright Popa Tiberiu 2011
// Use this as you wish
//import 'package:flutter/material.dart';
//import 'dart:convert';


class DES {
  // initial permutation table
  static final List<int> IP = [
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36,
    28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8, 57, 49, 41, 33,
    25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39,
    31, 23, 15, 7
  ];

  // inverse initial permutation
  static final List<int> invIP = [
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15,
    55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12,
    52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9,
    49, 17, 57, 25
  ];

  // Permutation P (in f(Feistel) function)
  static final List<int> P = [
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26,
    5, 18, 31, 10, 2, 8, 24, 14, 32, 27, 3, 9,
    19, 13, 30, 6, 22, 11, 4, 25
  ];

  // initial key permutation 64 => 56 bits
  static final List<int> PC1 = [
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34,
    26, 18, 10, 2, 59, 51, 43, 35, 27, 19, 11, 3,
    60, 52, 44, 36, 63, 55, 47, 39, 31, 23, 15, 7,
    62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37,
    29, 21, 13, 5, 28, 20, 12, 4
  ];

  // key permutation at round i 56 => 48
  static final List<int> PC2 = [
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32
  ];

  // key shift for each round
  static final List<int> keyShift = [
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1
  ];

  // expansion permutation from function f
  static final List<int> expandTbl = [
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11,
    12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21,
    20, 21, 22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29,
    30, 31, 32, 1
  ];

  // substitution boxes
  static final List<List<List<int>>> sboxes = [
    [
      [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
      [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
      [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
      [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]
    ],
    [
      [15, 1, 8, 14, 6, 11, 3, 2, 9, 7, 2, 13, 12, 0, 5, 10],
      [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
      [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
      [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]
    ],
    [
      [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
      [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
      [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
      [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]
    ],
    [
      [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
      [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
      [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
      [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]
    ],
    [
      [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
      [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
      [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
      [11, 8, 12, 7, 1, 14, 2, 12, 6, 15, 0, 9, 10, 4, 5, 3]
    ],
    [
      [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
      [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
      [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
      [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13]
    ],
    [
      [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
      [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
      [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
      [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12]
    ],
    [
      [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
      [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
      [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
      [2, 1, 14, 7, 4, 10, 18, 13, 15, 12, 9, 0, 3, 5, 6, 11]
    ]
  ];

  // holds subkeys (3 because we'll implement triple DES also)
static List<List<int>> K = [];
static List<List<int>> K1 = [];
static List<List<int>> K2 = [];


  static void setBit(List<int> data, int pos, int val) {
    int posByte = pos ~/ 8;
    int posBit = pos % 8;
    int tmpB = data[posByte];
    tmpB = (tmpB & (0xFF7F >> posBit)) & 0x00FF;
    int newByte = (val << (8 - (posBit + 1))) | tmpB;
    data[posByte] = newByte;
  }

  static int extractBit(List<int> data, int pos) {
    int posByte = pos ~/ 8;
    int posBit = pos % 8;
    int tmpB = data[posByte];
    int bit = (tmpB >> (8 - (posBit + 1))) & 0x0001;
    return bit;
  }

  static List<int> rotLeft(List<int> input, int len, int pas) {
    int nrBytes = ((len - 1) ~/ 8) + 1;
    List<int> out = List<int>.filled(nrBytes, 0);
    for (int i = 0; i < len; i++) {
      int val = extractBit(input, (i + pas) % len);
      setBit(out, i, val);
    }
    return out;
  }

  static List<int> extractBits(List<int> input, int pos, int n) {
    int numOfBytes = ((n - 1) ~/ 8) + 1;
    List<int> out = List<int>.filled(numOfBytes, 0);
    for (int i = 0; i < n; i++) {
      int val = extractBit(input, pos + i);
      setBit(out, i, val);
    }
    return out;
  }

  static List<int> permutFunc(List<int> input, List<int> table) {
    int nrBytes = ((table.length - 1) ~/ 8) + 1;
    List<int> out = List<int>.filled(nrBytes, 0);
    for (int i = 0; i < table.length; i++) {
      int val = extractBit(input, table[i] - 1);
      setBit(out, i, val);
    }
    return out;
  }

  static List<int> xorFunc(List<int> a, List<int> b) {
    List<int> out = List<int>.filled(a.length, 0);
    for (int i = 0; i < a.length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  static List<int> encrypt64Bloc(List<int> bloc, List<List<int>> subkeys, bool isDecrypt) {
    List<int> tmp = List<int>.from(bloc);
    List<int> R = List<int>.filled(bloc.length ~/ 2, 0);
    List<int> L = List<int>.filled(bloc.length ~/ 2, 0);

    tmp = permutFunc(bloc, IP);

    L = extractBits(tmp, 0, IP.length ~/ 2);
    R = extractBits(tmp, IP.length ~/ 2, IP.length ~/ 2);

    for (int i = 0; i < 16; i++) {
      List<int> tmpR = R;
      if (isDecrypt) {
        R = fFunc(R, subkeys[15 - i]);
      } else {
        R = fFunc(R, subkeys[i]);
      }
      R = xorFunc(L, R);
      L = tmpR;
    }

    tmp = concatBits(R, IP.length ~/ 2, L, IP.length ~/ 2);
    tmp = permutFunc(tmp, invIP);
    return tmp;
  }

  static List<int> fFunc(List<int> R, List<int> K) {
    List<int> tmp;
    tmp = permutFunc(R, expandTbl);
    tmp = xorFunc(tmp, K);
    tmp = sFunc(tmp);
    tmp = permutFunc(tmp, P);
    return tmp;
  }

  static List<int> sFunc(List<int> input) {
    input = separateBytes(input, 6);
    List<int> output = List<int>.filled(input.length ~/ 2, 0);
    int halfByte = 0;
    for (int b = 0; b < input.length; b++) {
      int valByte = input[b];
      int r = 2 * ((valByte >> 7) & 0x0001) + ((valByte >> 2) & 0x0001);
      int c = (valByte >> 3) & 0x000F;
      int val = sboxes[b][r][c];
      if (b % 2 == 0) {
        halfByte = val;
      } else {
        output[b ~/ 2] = (halfByte << 4) | val;
      }
    }
    return output;
  }

  static List<int> separateBytes(List<int> input, int len) {
    int numOfBytes = ((8 * input.length - 1) ~/ len) + 1;
    List<int> output = List<int>.filled(numOfBytes, 0);
    for (int i = 0; i < numOfBytes; i++) {
      for (int j = 0; j < len; j++) {
        int val = extractBit(input, len * i + j);
        setBit(output, 8 * i + j, val);
      }
    }
    return output;
  }

  static List<int> concatBits(List<int> a, int aLen, List<int> b, int bLen) {
    int numOfBytes = ((aLen + bLen - 1) ~/ 8) + 1;
    List<int> output = List<int>.filled(numOfBytes, 0);
    int j = 0;
    for (int i = 0; i < aLen; i++) {
      int val = extractBit(a, i);
      setBit(output, j, val);
      j++;
    }
    for (int i = 0; i < bLen; i++) {
      int val = extractBit(b, i);
      setBit(output, j, val);
      j++;
    }
    return output;
  }

 static List<int> deletePadding(List<int> input) {
  int count = 0;
  int i = input.length - 1;
  while (input[i] == 0) {
    count++;
    i--;
  }
  List<int> tmp = input.sublist(0, input.length - count);
  return tmp;
}


  static List<List<int>> generateSubKeys(List<int> key) {
    List<List<int>> tmp = List<List<int>>.filled(16, []);
    List<int> tmpK = permutFunc(key, PC1);

    List<int> C = extractBits(tmpK, 0, PC1.length ~/ 2);
    List<int> D = extractBits(tmpK, PC1.length ~/ 2, PC1.length ~/ 2);

    for (int i = 0; i < 16; i++) {
      C = rotLeft(C, 28, keyShift[i]);
      D = rotLeft(D, 28, keyShift[i]);
      List<int> cd = concatBits(C, 28, D, 28);
      tmp[i] = permutFunc(cd, PC2);
    }
    return tmp;
  }

  static List<int> encrypt(List<int> data, List<int> key) {
    int length = 0;
    List<int> padding = [0];
    int i;
    length = 8 - data.length % 8;
    padding = List<int>.filled(length, 0);
    padding[0] = 0x80;

    for (i = 1; i < length; i++) padding[i] = 0;

    List<int> tmp = List<int>.filled(data.length + length, 0);
    List<int> bloc = List<int>.filled(8, 0);

    K = generateSubKeys(key);
    int count = 0;

    for (i = 0; i < data.length + length; i++) {
      if (i > 0 && i % 8 == 0) {
        bloc = encrypt64Bloc(bloc, K, false);
        tmp.setRange(i - 8, i, bloc);
      }
      if (i < data.length) {
        bloc[i % 8] = data[i];
      } else {
        bloc[i % 8] = padding[count % 8];
        count++;
      }
    }
    if (bloc.length == 8) {
      bloc = encrypt64Bloc(bloc, K, false);
      tmp.setRange(i - 8, i, bloc);
    }
    return tmp;
  }

  static List<int> tripleDESEncrypt(List<int> data, List<List<int>> keys) {
    int length = 0;
    List<int> padding = [0];
    int i;

    length = 8 - data.length % 8;
    padding = List<int>.filled(length, 0);
    padding[0] = 0x80;

    for (i = 1; i < length; i++) padding[i] = 0;

    List<int> tmp = List<int>.filled(data.length + length, 0);
    List<int> bloc = List<int>.filled(8, 0);

    K = generateSubKeys(keys[0]);
    K1 = generateSubKeys(keys[1]);
    K2 = generateSubKeys(keys[2]);

    int count = 0;

    for (i = 0; i < data.length + length; i++) {
      if (i > 0 && i % 8 == 0) {
        bloc = encrypt64Bloc(bloc, K, false);
        bloc = encrypt64Bloc(bloc, K1, true);
        bloc = encrypt64Bloc(bloc, K2, false);
        tmp.setRange(i - 8, i, bloc);
      }
      if (i < data.length) {
        bloc[i % 8] = data[i];
      } else {
        bloc[i % 8] = padding[count % 8];
        count++;
      }
    }
    if (bloc.length == 8) {
      bloc = encrypt64Bloc(bloc, K, false);
      bloc = encrypt64Bloc(bloc, K1, true);
      bloc = encrypt64Bloc(bloc, K2, false);
      tmp.setRange(i - 8, i, bloc);
    }
    return tmp;
  }

  static List<int> tripleDESDecrypt(List<int> data, List<List<int>> keys) {
    int i;
    List<int> tmp = List<int>.filled(data.length, 0);
    List<int> bloc = List<int>.filled(8, 0);

    K = generateSubKeys(keys[0]);
    K1 = generateSubKeys(keys[1]);
    K2 = generateSubKeys(keys[2]);

    for (i = 0; i < data.length; i++) {
      if (i > 0 && i % 8 == 0) {
        bloc = encrypt64Bloc(bloc, K2, true);
        bloc = encrypt64Bloc(bloc, K1, false);
        bloc = encrypt64Bloc(bloc, K, true);
        tmp.setRange(i - 8, i, bloc);
      }
      if (i < data.length) bloc[i % 8] = data[i];
    }
    bloc = encrypt64Bloc(bloc, K2, true);
    bloc = encrypt64Bloc(bloc, K1, false);
    bloc = encrypt64Bloc(bloc, K, true);
    tmp.setRange(i - 8, i, bloc);

    tmp = deletePadding(tmp);

    return tmp;
  }

  static List<int> decrypt(List<int> data, List<int> key) {
    int i;
    List<int> tmp = List<int>.filled(data.length, 0);
    List<int> bloc = List<int>.filled(8, 0);

    K = generateSubKeys(key);

    for (i = 0; i < data.length; i++) {
      if (i > 0 && i % 8 == 0) {
        bloc = encrypt64Bloc(bloc, K, true);
        tmp.setRange(i - 8, i, bloc);
      }
      if (i < data.length) bloc[i % 8] = data[i];
    }
    bloc = encrypt64Bloc(bloc, K, true);
    tmp.setRange(i - 8, i, bloc);

    tmp = deletePadding(tmp);

    return tmp;
  }

}

void main() {
  // Sample string and DES key
  String data = "Hello, DES!";
  List<int> key = [0x13, 0x34, 0x57, 0x79, 0x9B, 0xBC, 0xDF, 0xF1];

  // Triple DES keys (24 bytes of 0)
  List<List<int>> keys = [
    [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  ];

  print('Original String: $data');
  print('DES Key: $key');
  print('Triple DES Keys: $keys');

  // Data bytes to encrypt
  List<int> dataBytes = [
    0x92, 0x03, 0x1a, 0xb7, 0xe2, 0x51, 0xb2, 0xda,
    0xc9, 0xcf, 0xaf, 0xac, 0x30, 0x8b, 0xc9, 0x8d,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  ];

  print('Original Data Bytes: ${dataBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Encrypt using DES
  List<int> encryptedData = DES.encrypt(dataBytes, key);
  print('Encrypted Data Bytes: ${encryptedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Decrypt using DES
  List<int> decryptedData = DES.decrypt(encryptedData, key);
  print('Decrypted Data Bytes: ${decryptedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Convert decrypted bytes back to string (if applicable)
  // String decryptedString = utf8.decode(decryptedData);
  // print('Decrypted String: $decryptedString');

  // Encrypt using Triple DES
  List<int> tripleEncryptedData = DES.tripleDESEncrypt(dataBytes, keys);
  print('Triple Encrypted Data Bytes: ${tripleEncryptedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Decrypt using Triple DES
  List<int> tripleDecryptedData = DES.tripleDESDecrypt(tripleEncryptedData, keys);
  print('Triple Decrypted Data Bytes: ${tripleDecryptedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Convert triple decrypted bytes back to string (if applicable)
  // String tripleDecryptedString = utf8.decode(tripleDecryptedData);
  // print('Triple Decrypted String: $tripleDecryptedString');
}
