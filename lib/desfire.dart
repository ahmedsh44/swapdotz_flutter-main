// lib/desfire.dart  –  helper for plain 3‑DES DESFire access
//
// This version includes fixes for file creation and application
// authentication.  See main.dart for usage.

import 'dart:math';
import 'dart:typed_data';
import 'package:dart_des/dart_des.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'dart:convert';
import 'package:pointycastle/export.dart' as pc;

class Desfire {
  Desfire(this.tag);

  final NFCTag tag;

  /* ---------- short trace helpers ---------- */
  String _hx(List<int> b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

  // Add chaining helpers
  int _sw1(List<int> r) => r.length >= 2 ? r[r.length - 2] : -1;
  int _sw2(List<int> r) => r.isNotEmpty ? r.last : -1;

  Future<Uint8List> _raw(List<int> cmd) async =>
      await FlutterNfcKit.transceive(Uint8List.fromList(cmd)) as Uint8List;

  Future<Uint8List> send(List<int> cmd) async {
    final r = await _raw(cmd);
    print('🔍 Command: ${_hx(cmd)}');
    print('🔍 Response: ${_hx(r)}');
    if (r.length < 2 || r[r.length - 2] != 0x91 || r.last != 0x00) {
      final status = r.length >= 2 ? _hx(r.sublist(r.length - 2)) : 'unknown';
      print('❌ Card error: $status');
      throw 'Card returned: $status';
    }
    return r.sublist(0, r.length - 2);
  }

  Future<Uint8List> _send(List<int> cmd) async {
    return await send(cmd);
  }

  /// Send first frame (native cmd) + continuation frames (0xAF ...)
  /// `first` is the full first APDU (incl. CLA INS P1 P2 Lc ... Le)
  /// `getNext` generates the next continuation APDU (usually 0xAF + chunk)
  Future<Uint8List> _sendChained({
    required List<int> first,
    required List<int> Function() getNext,
    bool collectData = false, // true for ReadData; false for WriteData
  }) async {
    final collected = <int>[];

    var r = await _raw(first);
    print('🔗 First-frame resp: ${_hx(r)}');

    // For reads we may receive data bytes before SW1/SW2
    if (collectData && r.length > 2) {
      collected.addAll(r.sublist(0, r.length - 2));
    }

    while (_sw1(r) == 0x91 && _sw2(r) == 0xAF) {
      final next = getNext();
      r = await _raw(next);
      print('🔗 Cont-frame resp: ${_hx(r)}');
      if (collectData && r.length > 2) {
        collected.addAll(r.sublist(0, r.length - 2));
      }
    }

    // Final status must be 91 00
    if (!(_sw1(r) == 0x91 && _sw2(r) == 0x00)) {
      final status = r.length >= 2 ? _hx(r.sublist(r.length - 2)) : 'unknown';
      throw 'Card returned: $status';
    }

    return collectData ? Uint8List.fromList(collected) : Uint8List(0);
  }

  /* ---------- authenticate legacy key‑0 ---------- */
  Future<void> authenticateLegacy() async {
    print('🔐 Starting legacy authentication...');
    const zeroKey = <int>[
      0, 0, 0, 0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, 0, 0, 0
    ];
    final des = DES3(
      key: Uint8List.fromList([...zeroKey, ...zeroKey.sublist(0, 8)]),
      mode: DESMode.CBC,
      iv: Uint8List(8),
      paddingType: DESPaddingType.None,
    );

    // step‑1
    print('🔐 Step 1: Sending authenticate command...');
    final resp1 =
        await _raw([0x90, 0x0A, 0x00, 0x00, 0x01, 0x00, 0x00]); // expect 91 AF
    print('🔐 Step 1 response: ${_hx(resp1)}');
    if (resp1.last != 0xAF) {
      print(
          '❌ Authentication step 1 failed - expected 0xAF, got 0x${resp1.last.toRadixString(16)}');
      throw 'Authenticate step‑1 failed';
    }
    final encRndB = resp1.sublist(0, 8);
    final rndB = des.decrypt(encRndB);
    print('🔐 Decrypted RndB: ${_hx(rndB)}');

    // create RndA
    final rndA = Uint8List.fromList(
        List.generate(8, (_) => Random.secure().nextInt(256)));
    print('🔐 Generated RndA: ${_hx(rndA)}');
    final rndBrot = [...rndB.sublist(1), rndB[0]];
    final encAB = des.encrypt(Uint8List.fromList([...rndA, ...rndBrot]));
    print('🔐 Encrypted RndA+RndB: ${_hx(encAB)}');

    // step‑2
    print('🔐 Step 2: Sending authentication response...');
    await _send([0x90, 0xAF, 0x00, 0x00, 0x10, ...encAB, 0x00]);
    print('✅ Authentication successful!');
  }

  /* ---------- authenticate with specific key ---------- */
  Future<void> authenticateWithKey(int keyNumber) async {
    print('🔐 Starting authentication with key $keyNumber...');
    const zeroKey = <int>[
      0, 0, 0, 0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, 0, 0, 0
    ];
    final des = DES3(
      key: Uint8List.fromList([...zeroKey, ...zeroKey.sublist(0, 8)]),
      mode: DESMode.CBC,
      iv: Uint8List(8),
      paddingType: DESPaddingType.None,
    );

    // step‑1
    print('🔐 Key $keyNumber Step 1: Sending authenticate command...');
    final resp1 =
        await _raw([0x90, 0x0A, 0x00, 0x00, 0x01, keyNumber, 0x00]); // authenticate with specific key
    print('🔐 Key $keyNumber Step 1 response: ${_hx(resp1)}');
    if (resp1.last != 0xAF) {
      print(
          '❌ Key $keyNumber authentication step 1 failed - expected 0xAF, got 0x${resp1.last.toRadixString(16)}');
      throw 'Key $keyNumber authenticate step‑1 failed';
    }
    final encRndB = resp1.sublist(0, 8);
    final rndB = des.decrypt(encRndB);
    print('🔐 Key $keyNumber Decrypted RndB: ${_hx(rndB)}');

    // create RndA
    final rndA = Uint8List.fromList(
        List.generate(8, (_) => Random.secure().nextInt(256)));
    print('🔐 Key $keyNumber Generated RndA: ${_hx(rndA)}');
    final rndBrot = [...rndB.sublist(1), rndB[0]];
    final encAB = des.encrypt(Uint8List.fromList([...rndA, ...rndBrot]));
    print('🔐 Key $keyNumber Encrypted RndA+RndB: ${_hx(encAB)}');

    // step‑2
    print('🔐 Key $keyNumber Step 2: Sending authentication response...');
    await _send([0x90, 0xAF, 0x00, 0x00, 0x10, ...encAB, 0x00]);
    print('✅ Key $keyNumber authentication successful!');
  }

  /* ---------- try different keys ---------- */
  Future<void> tryDifferentKeys() async {
    print('🔍 Trying different authentication keys...');
    for (int keyNum = 0; keyNum < 4; keyNum++) {
      try {
        print('\n🔑 Testing key $keyNum:');
        await authenticateWithKey(keyNum);

        // Test if this key allows file access
        print('🧪 Testing file access with key $keyNum...');
        try {
          await getFileInfo();
          print('✅ Key $keyNum allows file access!');
          return; // Found working key, exit
        } catch (e) {
          print('❌ Key $keyNum does not allow file access: $e');
        }
      } catch (e) {
        print('❌ Key $keyNum authentication failed: $e');
      }
    }
    print('❌ No working key found among keys 0-3');
  }

  /* ---------- authenticate at application level ---------- */
  Future<void> authenticateApplication() async {
    print('🔐 Starting application-level authentication...');
    const zeroKey = <int>[
      0, 0, 0, 0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, 0, 0, 0
    ];
    final des = DES3(
      key: Uint8List.fromList([...zeroKey, ...zeroKey.sublist(0, 8)]),
      mode: DESMode.CBC,
      iv: Uint8List(8),
      paddingType: DESPaddingType.None,
    );
    // step‑1
    print('🔐 App Step 1: Sending authenticate command...');
    final resp1 =
        await _raw([0x90, 0x0A, 0x00, 0x00, 0x01, 0x00, 0x00]); // expect 91 AF
    print('🔐 App Step 1 response: ${_hx(resp1)}');
    if (resp1.last != 0xAF) {
      print(
          '❌ Application authentication step 1 failed - expected 0xAF, got 0x${resp1.last.toRadixString(16)}');
      throw 'Application authenticate step‑1 failed';
    }
    final encRndB = resp1.sublist(0, 8);
    final rndB = des.decrypt(encRndB);
    print('🔐 App Decrypted RndB: ${_hx(rndB)}');
    // create RndA
    final rndA = Uint8List.fromList(
        List.generate(8, (_) => Random.secure().nextInt(256)));
    print('🔐 App Generated RndA: ${_hx(rndA)}');
    final rndBrot = [...rndB.sublist(1), rndB[0]];
    final encAB = des.encrypt(Uint8List.fromList([...rndA, ...rndBrot]));
    print('🔐 App Encrypted RndA+RndB: ${_hx(encAB)}');
    // step‑2
    print('🔐 App Step 2: Sending authentication response...');
    await _send([0x90, 0xAF, 0x00, 0x00, 0x10, ...encAB, 0x00]);
    print('✅ Application-level authentication successful!');
  }

  /* ---------- one‑time setup (idempotent) ---------- */
  Future<void> ensureAppAndFileExist() async {
    print('📱 Setting up DESFire application and file...');
    // We assume PICC level authentication has been performed before calling this.
    // First select the master application (AID 000000)
    print('📱 Selecting master application AID: 000000');
    await _send([0x90, 0x5A, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00]);
    print('✅ Master application selected successfully');
    // Try to create our application (AID: 000001) at master level
    try {
      print('📱 Creating application (if it doesn\'t exist)...');
      await _send(
          [0x90, 0xCA, 0x00, 0x00, 0x05, 0x01, 0x00, 0x00, 0x0F, 0x01, 0x00]);
      print('✅ Application created/verified');
    } catch (e) {
      print('ℹ️  Application already exists or creation failed: $e');
    }
    // Select our application
    print('📱 Selecting application AID: 000001');
    await _send([0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00]);
    print('✅ Application selected successfully');
    // Authenticate at application level before creating files
    print('🔐 Authenticating at application level...');
    await authenticateApplication();
    print('✅ Application-level authentication successful');
    // Try to create StdData file 01 (plain, 256 B)
    try {
      print('📱 Creating file 01 (if it doesn\'t exist)...');
      // According to the APDU spec the Le byte (0x00) must be appended to the
      // command even if no response data is expected. Without this the card
      // returns 0x91 0x7E (length error).
      await _send([
        0x90,
        0xCD,
        0x00,
        0x00,
        0x07,
        0x01, // file 01
        0x00, // Comm = plain
        0x00,
        0x00, // access rights: key‑0 everywhere
        0x00,
        0x01,
        0x00, // size 0x0100 (256 bytes)
        0x00 // Le
      ]);
      print('✅ File 01 created successfully');
    } catch (e) {
      print('ℹ️  File 01 already exists or creation failed: $e');
    }

    // Re-authenticate at application level to ensure subsequent operations
    // such as WriteData/ReadData have a valid session key.  The create file
    // command may reset the authentication state.
    print('🔐 Re-authenticating at application level after setup...');
    await authenticateApplication();
    print('✅ Application-level re-authentication successful');
  }

  /* ---------- read file information ---------- */
  Future<void> getFileInfo() async {
    print('📋 Getting file information...');
    // Do not swallow errors here so the caller can decide what to do
    final result = await _send([
      0x90,
      0xF5, // GetFileSettings command
      0x00,
      0x00,
      0x01,
      0x01, // file 01
      0x00
    ]);
    print('📋 File info: ${_hx(result)}');
  }

  /* ---------- test read operation ---------- */
  Future<void> testReadFile() async {
    print('🧪 Testing read operation...');
    try {
      final result = await readFile01(11);
      print('✅ Read test successful: ${utf8.decode(result)}');
    } catch (e) {
      print('❌ Read test failed: $e');
    }
  }

  /* ---------- plain read / write ---------- */
  // Replace the entire writeFile01 with this
  Future<void> writeFile01(Uint8List data) async {
    final total = data.length;
    print('✍️  Writing $total bytes to file 01 (chained)...');

    // Safe per-frame data budget to avoid 91 7e; adjust if you like
    const chunkSize = 40;

    final header = <int>[
      0x01,              // file 01
      0x00, 0x00, 0x00,  // offset = 0 (LSB..MSB)
      total & 0xFF, (total >> 8) & 0xFF, (total >> 16) & 0xFF, // length (LSB..MSB)
    ];

    int pos = 0;
    final firstChunkEnd = (total < chunkSize) ? total : chunkSize;
    final firstChunk = data.sublist(0, firstChunkEnd);

    final first = <int>[
      0x90, 0x3D, 0x00, 0x00,            // CLA INS P1 P2
      7 + firstChunk.length,             // Lc
      ...header,
      ...firstChunk,
      0x00                               // Le
    ];

    // Remaining chunks will be sent with 0xAF frames
    List<int> mkCont() {
      final start = pos == 0 ? firstChunkEnd : pos;
      final end = (start + chunkSize > total) ? total : start + chunkSize;
      final chunk = data.sublist(start, end);
      pos = end;
      return <int>[0x90, 0xAF, 0x00, 0x00, chunk.length, ...chunk, 0x00];
    }

    await _sendChained(first: first, getNext: mkCont, collectData: false);
    print('✅ Chunked write complete');
  }

  // Replace the entire readFile01 with this
  Future<Uint8List> readFile01(int len) async {
    print('📄 Reading $len bytes from file 01 (chained)...');
    final header = <int>[
      0x01,              // file 01
      0x00, 0x00, 0x00,  // offset = 0
      len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF,
    ];

    final first = <int>[
      0x90, 0xBD, 0x00, 0x00,
      0x07,
      ...header,
      0x00
    ];

    // For ReadData, continuation frames are empty 0xAF frames with Lc=0
    List<int> mkCont() => <int>[0x90, 0xAF, 0x00, 0x00, 0x00];

    final result = await _sendChained(first: first, getNext: mkCont, collectData: true);
    print('📄 Read data (${result.length} B): ${_hx(result)}');
    return result;
  }

  /// Change file 01 to MACed comms (no plaintext) - prototype without SM
  Future<void> setFile01MacMode() async {
    print('🔧 Changing file 01 to MACed comm mode...');
    // Ensure application 000001 is selected
    await _send([0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00]);
    // ChangeFileSettings (0x5F): CommSetting(1 byte) + AccessRights(2 bytes)
    // CommSetting 0x01 = MACed; keep access rights 0x0000 (prototype)
    await _send([0x90, 0x5F, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00]);
    print('✅ File 01 now set to MACed comm (prototype)');
  }

  /* ---------- AES/CMAC helpers (local only) ---------- */
  Uint8List _aesEcbEncrypt(Uint8List key, Uint8List data) {
    final cipher = pc.BlockCipher('AES/ECB');
    cipher.init(true, pc.KeyParameter(key));
    final out = Uint8List(data.length);
    for (int offset = 0; offset < data.length; offset += 16) {
      cipher.processBlock(data, offset, out, offset);
    }
    return out;
  }

  Uint8List _cmac(Uint8List key, Uint8List message) {
    final cmac = pc.CMac(pc.BlockCipher('AES'), 128);
    cmac.init(pc.KeyParameter(key));
    cmac.update(message, 0, message.length);
    final mac = Uint8List(16);
    cmac.doFinal(mac, 0);
    return mac;
  }

  /// Example: Perform AES authenticate (EV1/EV2 style placeholder)
  Future<void> authenticateAes({required Uint8List aesKey, int keyNo = 0}) async {
    print('🔐 AES auth (local prototype) with keyNo=$keyNo');
    // Native AES auth command: 0xAA for Authenticate AES (ev1); many stacks use 0xAA or 0x1A
    final resp1 = await _raw([0x90, 0xAA, 0x00, 0x00, 0x01, keyNo & 0xFF, 0x00]);
    print('🔐 AES Step 1 response: ${_hx(resp1)}');
    if (resp1.isEmpty || resp1.last != 0xAF) {
      throw 'AES auth step-1 failed';
    }
    final encRndB = resp1.sublist(0, resp1.length - 2);
    final rndB = _aesEcbEncrypt(aesKey, Uint8List.fromList(encRndB)); // placeholder

    // Generate RndA
    final rndA = Uint8List.fromList(List.generate(16, (_) => Random.secure().nextInt(256)));
    final rndBrot = [...rndB.sublist(1), rndB[0]];
    final encAB = _aesEcbEncrypt(aesKey, Uint8List.fromList([...rndA, ...rndBrot]));

    final resp2 = await _raw([0x90, 0xAF, 0x00, 0x00, encAB.length, ...encAB, 0x00]);
    print('🔐 AES Step 2 response: ${_hx(resp2)}');
    if (resp2.length < 18 || resp2[resp2.length - 2] != 0x91 || resp2.last != 0x00) {
      throw 'AES auth step-2 failed';
    }
    // In a real impl: extract RndA' from response and verify rotation.
    print('✅ AES authentication (prototype) complete');
  }
}


