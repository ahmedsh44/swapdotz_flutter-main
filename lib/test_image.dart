import 'package:flutter/material.dart';

class TestImageWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Image Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Testing Image Loading...'),
            SizedBox(height: 20),
            // Test with a simple image first
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/marketplace_images/inspired_by_legends/skywalker_legacy.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Image error: $error');
                    return Container(
                      color: Colors.red,
                      child: Center(
                        child: Text('ERROR: $error'),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: 20),
            // Test with a different image
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/marketplace_images/regular/cool_blue_swapdot.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Image error: $error');
                    return Container(
                      color: Colors.red,
                      child: Center(
                        child: Text('ERROR: $error'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 