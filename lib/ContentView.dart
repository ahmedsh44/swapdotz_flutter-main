import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ContentView(),
    );
  }
}

class ContentView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NFC Reader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.language,
              size: 80,
              color: Theme.of(context).colorScheme.secondary,
            ),
            SizedBox(height: 20),
            NFCReaderView(),
            SizedBox(height: 20),
            MyViewControllerWrapper(),
          ],
        ),
      ),
    );
  }
}

class NFCReaderView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 600,
      height: 600,
      color: Colors.blue[100],
      child: Center(
        child: Text(
          'NFC Reader View',
          style: TextStyle(fontSize: 24, color: Colors.blue),
        ),
      ),
    );
  }
}

class MyViewControllerWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 600,
      height: 600,
      color: Colors.green[100],
      child: Center(
        child: Text(
          'My View Controller Wrapper',
          style: TextStyle(fontSize: 24, color: Colors.green),
        ),
      ),
    );
  }
}

