import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ViewController(),
    );
  }
}

class ViewController extends StatefulWidget {
  @override
  _ViewControllerState createState() => _ViewControllerState();
}

class _ViewControllerState extends State<ViewController> {
  NFCTag? _connectedTag;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NFC Scanner'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _startScanning,
          child: Text('Start Scanning'),
        ),
      ),
    );
  }

  void _startScanning() async {
    try {
      NFCTag tag = await FlutterNfcKit.poll();
      print("Tag: ${tag.id}");
      setState(() {
        _connectedTag = tag;
      });

      if (_connectedTag != null) {
        print("Tag detected");
        switch (_connectedTag!.type) {
          case NFCTagType.mifare_desfire:
            print("DESFire Tag");
            break;
          case NFCTagType.mifare_ultralight:
            print("MIFARE Ultralight Tag");
            break;
          case NFCTagType.mifare_classic:
            print("MIFARE Classic Tag");
            break;
          case NFCTagType.iso7816:
            print("ISO 7816 Tag");
            _sendMifareCommand([0x1A, 0x00]);
            break;
          case NFCTagType.iso15693:
            print("ISO 15693 Tag");
            break;
          default:
            print("Unknown Tag");
        }
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  void _sendMifareCommand(List<int> command) async {
    if (_connectedTag != null) {
      try {
        var result = await FlutterNfcKit.transceive(command);
        print("Response Data: $result");
        result.forEach((byte) {
          print("0x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}");
        });
      } catch (e) {
        print("Error: $e");
      }
    }
  }
}

