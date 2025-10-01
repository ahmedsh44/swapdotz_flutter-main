import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

class NFCReaderView extends StatefulWidget {
  @override
  _NFCReaderViewState createState() => _NFCReaderViewState();
}

class _NFCReaderViewState extends State<NFCReaderView> {
  NFCTag? _connectedTag;
  late final NFCTagReaderSession _tagReaderSession;

  @override
  void initState() {
    super.initState();
  }

  void _startScanning() async {
    try {
      _tagReaderSession = NFCTagReaderSession(
        pollingOption: NFCPollingOption.iso14443.union(NFCPollingOption.iso15693),
        delegate: this,
      );
      _tagReaderSession.alertMessage = "Hold your device near the item to learn more about it.";
      _tagReaderSession.begin();
    } catch (e) {
      print("Error starting NFC scan: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: _startScanning,
          child: Text('Start Scanning'),
        ),
      ),
    );
  }
}

extension on NFCTagReaderSession {
  void didBecomeActive() {
    print("Session became active");
  }

  void didInvalidateWithError(Exception error) {
    print("Session invalidated: ${error.toString()}");
  }

  void didDetectTags(List<NFCTag> tags) {
    if (tags.isNotEmpty) {
      final firstTag = tags.first;
      if (firstTag.type == NFCTagType.iso7816) {
        print("ISO 7816 tag detected: $firstTag");
      } else if (firstTag.type == NFCTagType.mifare) {
        print("MiFare tag detected: $firstTag");
      } else {
        print("Other tag detected");
      }
    }
  }
}

class NFCTagReaderSession {
  final NFCPollingOption pollingOption;
  final _NFCReaderViewState delegate;
  String? alertMessage;

  NFCTagReaderSession({
    required this.pollingOption,
    required this.delegate,
  });

  void begin() {
    delegate._startScanning();
  }
}

class NFCPollingOption {
  static const NFCPollingOption iso14443 = NFCPollingOption._(0);
  static const NFCPollingOption iso15693 = NFCPollingOption._(1);
  static const NFCPollingOption iso18092 = NFCPollingOption._(2);

  final int value;

  const NFCPollingOption._(this.value);

  NFCPollingOption union(NFCPollingOption other) {
    return NFCPollingOption._(value | other.value);
  }
}

class NFCTag {
  final NFCTagType type;
  const NFCTag(this.type);
}

enum NFCTagType { iso7816, mifare }
