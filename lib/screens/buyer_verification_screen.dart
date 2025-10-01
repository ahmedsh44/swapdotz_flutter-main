import 'package:flutter/material.dart';
import '../models/seller_verification_session.dart';
import '../services/seller_verification_service.dart';

class BuyerVerificationScreen extends StatefulWidget {
  @override
  _BuyerVerificationScreenState createState() => _BuyerVerificationScreenState();
}

class _BuyerVerificationScreenState extends State<BuyerVerificationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text('My Purchases'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<SellerVerificationSession>>(
        stream: SellerVerificationService.getBuyerVerificationSessions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, color: Colors.red, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Error loading purchases',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final sessions = snapshot.data ?? [];
          final pendingSessions = sessions.where((s) => 
            s.status == SellerVerificationStatus.nfc_verified && !s.isExpired
          ).toList();
          final otherSessions = sessions.where((s) => 
            s.status != SellerVerificationStatus.nfc_verified || s.isExpired
          ).toList();

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag, color: Colors.grey[600], size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No Purchases Yet',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your SwapDot purchases will appear here',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pendingSessions.isNotEmpty) ...[
                  _buildSectionHeader('📦 Ready to Receive', pendingSessions.length),
                  SizedBox(height: 8),
                  Text(
                    'Seller has verified ownership. Waiting for shipping/delivery.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  SizedBox(height: 12),
                  ...pendingSessions.map((session) => _buildPurchaseCard(session, true)),
                  SizedBox(height: 24),
                ],
                
                if (otherSessions.isNotEmpty) ...[
                  _buildSectionHeader('📋 All Purchases', otherSessions.length),
                  SizedBox(height: 12),
                  ...otherSessions.map((session) => _buildPurchaseCard(session, false)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseCard(SellerVerificationSession session, bool isAwaitingDelivery) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAwaitingDelivery ? Colors.blue.withOpacity(0.1) : Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAwaitingDelivery ? Colors.blue : Colors.grey[800]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SwapDot: ${session.tokenId}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Paid: \$${session.amount.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.green, fontSize: 14),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(session.status),
            ],
          ),
          
          SizedBox(height: 12),
          
          Text(
            _getStatusDescription(session),
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          
          if (session.isNfcVerified) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.verified, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text(
                  'Seller verified ownership ${_formatDate(session.nfcVerifiedAt!)}',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ],
          
          if (!session.isExpired && !session.isCompleted) ...[
            SizedBox(height: 8),
            Text(
              'Time remaining: ${session.timeRemainingText}',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
          
          SizedBox(height: 16),
          
          _buildActionButtons(session),
        ],
      ),
    );
  }

  Widget _buildStatusChip(SellerVerificationStatus status) {
    Color chipColor;
    switch (status) {
      case SellerVerificationStatus.pending_nfc_scan:
        chipColor = Colors.orange;
        break;
      case SellerVerificationStatus.nfc_verified:
        chipColor = Colors.blue;
        break;
      case SellerVerificationStatus.completed:
        chipColor = Colors.green;
        break;
      case SellerVerificationStatus.expired:
        chipColor = Colors.red;
        break;
      case SellerVerificationStatus.cancelled:
        chipColor = Colors.grey;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getBuyerStatusText(status),
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getBuyerStatusText(SellerVerificationStatus status) {
    switch (status) {
      case SellerVerificationStatus.pending_nfc_scan:
        return 'Awaiting Seller';
      case SellerVerificationStatus.nfc_verified:
        return 'Shipping';
      case SellerVerificationStatus.completed:
        return 'Completed';
      case SellerVerificationStatus.expired:
        return 'Expired';
      case SellerVerificationStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _getStatusDescription(SellerVerificationSession session) {
    switch (session.status) {
      case SellerVerificationStatus.pending_nfc_scan:
        return 'Waiting for seller to verify they have the SwapDot';
      case SellerVerificationStatus.nfc_verified:
        return 'Seller has verified ownership. SwapDot should be shipping to you.';
      case SellerVerificationStatus.completed:
        return 'Transaction completed. You now own this SwapDot!';
      case SellerVerificationStatus.expired:
        return 'Purchase expired. You should receive an automatic refund.';
      case SellerVerificationStatus.cancelled:
        return 'Purchase was cancelled. You should receive a refund.';
    }
  }

  Widget _buildActionButtons(SellerVerificationSession session) {
    if (session.status == SellerVerificationStatus.nfc_verified && !session.isExpired) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _completeTransaction(session),
              icon: Icon(Icons.check_circle, size: 18),
              label: Text('I Received the SwapDot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Only tap this when you physically receive the SwapDot',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (session.status == SellerVerificationStatus.pending_nfc_scan) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.hourglass_empty, color: Colors.orange, size: 20),
            SizedBox(height: 4),
            Text(
              'Waiting for seller verification',
              style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              'Seller needs to scan the SwapDot to prove they have it',
              style: TextStyle(color: Colors.grey[400], fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      return SizedBox(); // No actions for completed/expired sessions
    }
  }

  Future<void> _completeTransaction(SellerVerificationSession session) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Complete Purchase', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please confirm that you have physically received the SwapDot.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ This will:',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• Transfer digital ownership to you',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '• Release payment to the seller',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '• Complete the transaction',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Only confirm if you have the physical SwapDot in hand.',
              style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Yes, I Received It'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Completing transaction...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      await SellerVerificationService.completeTransaction(session.sessionId);

      Navigator.pop(context); // Close loading dialog

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Transaction completed! You now own this SwapDot.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to complete transaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'today at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else {
      return '${difference.inDays} days ago';
    }
  }
} 