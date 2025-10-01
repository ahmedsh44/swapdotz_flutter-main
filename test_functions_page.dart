import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TestFunctionsPage extends StatefulWidget {
  const TestFunctionsPage({super.key});

  @override
  State<TestFunctionsPage> createState() => _TestFunctionsPageState();
}

class _TestFunctionsPageState extends State<TestFunctionsPage> {
  final FirebaseFunctions functions = FirebaseFunctions.instance;
  String _result = '';
  bool _isLoading = false;

  Future<void> _testBeginAuthenticate() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing beginAuthenticate...';
    });

    try {
      final HttpsCallable callable = functions.httpsCallable('beginAuthenticate');
      final result = await callable.call(<String, dynamic>{
        'userId': 'test_user_123',
        'cardId': 'test_card_456',
        // Add other required parameters based on your function
      });
      
      setState(() {
        _result = 'Success: ${result.data}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Similar methods for other functions...
  Future<void> _testChangeKey() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing changeKey...';
    });

    try {
      final HttpsCallable callable = functions.httpsCallable('changeKey');
      final result = await callable.call(<String, dynamic>{
        'userId': 'test_user_123',
        'oldKey': 'old_key_value',
        'newKey': 'new_key_value',
      });
      
      setState(() {
        _result = 'Success: ${result.data}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Firebase Functions'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _testBeginAuthenticate,
              child: const Text('Test beginAuthenticate'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testChangeKey,
              child: const Text('Test changeKey'),
            ),
            const SizedBox(height: 16),
            if (_isLoading) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _result,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}