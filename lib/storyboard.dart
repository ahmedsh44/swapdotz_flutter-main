import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ViewController(),
    );
  }
}

class ViewController extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('View Controller'),
      ),
      body: Container(
        color: Theme.of(context).colorScheme.background,
        child: Center(
          child: Text('Content goes here'),
        ),
      ),
    );
  }
}
