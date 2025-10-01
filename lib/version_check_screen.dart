import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class VersionCheckScreen extends StatelessWidget {
  final String currentVersion;
  final String requiredVersion;
  final String? updateUrl;
  final String? updateMessage;

  const VersionCheckScreen({
    Key? key,
    required this.currentVersion,
    required this.requiredVersion,
    this.updateUrl,
    this.updateMessage,
  }) : super(key: key);

  Future<void> _launchStore() async {
    String url;
    if (updateUrl != null) {
      url = updateUrl!;
    } else if (Platform.isIOS) {
      // Replace with your actual App Store ID
      url = 'https://apps.apple.com/app/swapdotz/id1234567890';
    } else if (Platform.isAndroid) {
      // Replace with your actual package name
      url = 'https://play.google.com/store/apps/details?id=com.swapdotz.app';
    } else {
      return;
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(
                  Icons.system_update,
                  size: 80,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Update Required',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your app version is outdated and must be updated to continue.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Version:',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          currentVersion,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Required Version:',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          requiredVersion,
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (updateMessage != null && updateMessage!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          updateMessage!,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _launchStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.update, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Update Now',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This update is mandatory for security reasons',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 