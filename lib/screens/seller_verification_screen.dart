import 'package:flutter/material.dart';
import '../models/seller_verification_session.dart';
import '../services/seller_verification_service.dart';

class SellerVerificationScreen extends StatefulWidget {
  @override
  _SellerVerificationScreenState createState() => _SellerVerificationScreenState();
}

class _SellerVerificationScreenState extends State<SellerVerificationScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text('Seller Verification'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<SellerVerificationSession>>(
        stream: SellerVerificationService.getSellerVerificationSessions(),
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
                    'Error loading verification sessions',
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
          final pendingSessions = sessions.where((s) => s.status == SellerVerificationStatus.pending_nfc_scan && !s.isExpired).toList();
          final completedSessions = sessions.where((s) => s.status != SellerVerificationStatus.pending_nfc_scan).toList();

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, color: Colors.grey[600], size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No Verification Sessions',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'When someone buys your SwapDotz, you\'ll need to verify ownership here',
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
                  _buildSectionHeader('🚨 Action Required', pendingSessions.length),
                  SizedBox(height: 12),
                  ...pendingSessions.map((session) => _buildVerificationCard(session, true)),
                  SizedBox(height: 24),
                ],
                
                if (completedSessions.isNotEmpty) ...[
                  _buildSectionHeader('📋 All Sessions', completedSessions.length),
                  SizedBox(height: 12),
                  ...completedSessions.map((session) => _buildVerificationCard(session, false)),
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

  Widget _buildVerificationCard(SellerVerificationSession session, bool isPending) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPending ? Colors.orange.withOpacity(0.1) : Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending ? Colors.orange : Colors.grey[800]!,
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
                      'Token: ${session.tokenId}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sale Amount: \$${session.amount.toStringAsFixed(2)}',
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
            session.status.description,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          
          if (!session.isExpired && session.status == SellerVerificationStatus.pending_nfc_scan) ...[
            SizedBox(height: 8),
            Text(
              'Time remaining: ${session.timeRemainingText}',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
          
          if (session.isNfcVerified) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text(
                  'NFC Verified ${_formatDate(session.nfcVerifiedAt!)}',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
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
        status.displayName,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButtons(SellerVerificationSession session) {
    if (session.status == SellerVerificationStatus.pending_nfc_scan && !session.isExpired) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _verifyOwnership(session),
              icon: Icon(Icons.nfc, size: 18),
              label: Text('Scan SwapDot to Verify'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => _cancelSession(session),
            child: Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red),
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      );
    } else if (session.status == SellerVerificationStatus.nfc_verified) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _completeTransaction(session),
              icon: Icon(Icons.send, size: 18),
              label: Text('Complete Transaction'),
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
        ],
      );
    } else {
      return SizedBox(); // No actions for completed/expired sessions
    }
  }

  Future<void> _verifyOwnership(SellerVerificationSession session) async {
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
                'Hold your SwapDot near the device...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Perform NFC verification
      final updatedSession = await SellerVerificationService.verifyOwnershipWithNFC(
        sessionId: session.sessionId,
        tokenId: session.tokenId,
      );

      Navigator.pop(context); // Close loading dialog

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ SwapDot verified successfully! You can now ship or transfer it.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Verification failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _completeTransaction(SellerVerificationSession session) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Complete Transaction', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will transfer ownership of the SwapDot to the buyer. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Complete Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SellerVerificationService.completeTransaction(session.sessionId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Transaction completed! Ownership transferred to buyer.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to complete transaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelSession(SellerVerificationSession session) async {
    // Show reason dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        String selectedReason = 'item_not_available';
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Cancel Sale', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Why are you cancelling this sale? The buyer will be refunded.',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedReason,
                dropdownColor: Colors.grey[800],
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'item_not_available', child: Text('Item no longer available')),
                  DropdownMenuItem(value: 'item_damaged', child: Text('Item is damaged')),
                  DropdownMenuItem(value: 'shipping_issues', child: Text('Cannot ship to buyer')),
                  DropdownMenuItem(value: 'other', child: Text('Other reason')),
                ],
                onChanged: (value) => selectedReason = value!,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Keep Sale'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedReason),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Cancel & Refund'),
            ),
          ],
        );
      },
    );

    if (reason == null) return;

    try {
      await SellerVerificationService.cancelVerificationSession(session.sessionId, reason);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Sale cancelled. Buyer will be refunded.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to cancel sale: $e'),
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