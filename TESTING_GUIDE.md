# 🧪 Secure Transfer Testing Guide

## ✅ **System Successfully Deployed!**

The secure two-phase transfer system has been deployed with:

- **`initiateSecureTransfer`** - Creates pending transfers (owner only)
- **`finalizeSecureTransfer`** - Atomic ownership transfer (receiver)  
- **`cleanupExpiredPendings`** - Auto-cleanup of expired transfers
- **Updated Firestore Rules** - Enforcing security policies

## 🧪 **Testing Scenarios**

### **Test 1: Normal Transfer Flow**

1. **Start the Flutter app** 
2. **Owner scans token** → Should see "🔒 Secure Transfer Started!"
3. **Receiver scans same token** → Should see "🎉 Transfer successful!"
4. **Verify ownership changed** → Check token owner in UI

**Expected Flow:**
```
Owner Scan → initiateSecureTransfer() → "Hand to recipient within 10 minutes"
Receiver Scan → finalizeSecureTransfer() → "You are now the owner!"
```

### **Test 2: Security Validation**

1. **Non-owner tries to initiate transfer**
   - Expected: "Only the current owner can initiate transfers"

2. **Multiple pending transfers**
   - Expected: "A transfer is already in progress"

3. **Expired transfer (wait 10+ minutes)**
   - Expected: "Transfer expired. Please start a new transfer"

### **Test 3: Error Handling**

1. **Network issues**
   - Should fallback gracefully to legacy system

2. **Authentication required**
   - Should prompt for sign-in

3. **Invalid token**
   - Should show appropriate error message

## 📊 **Monitoring & Logs**

### **Firebase Functions Logs**
```bash
cd firebase
firebase functions:log --only initiateSecureTransfer,finalizeSecureTransfer
```

### **Look for these log entries:**
- ✅ "Starting secure transfer..."
- ✅ "Secure transfer initiated!"  
- ✅ "Claiming SwapDot..."
- ✅ "Transfer successful!"
- ❌ "Secure transfer failed, falling back to legacy"

### **Database Collections to Monitor**

1. **`tokens/{tokenId}`** - Check ownership changes
   ```
   ownerUid: "new-owner-id"
   counter: incrementing
   status: "OK" 
   previous_owners: [old-owner-id, ...]
   ```

2. **`pendingTransfers/{tokenId}`** - Check transfer states
   ```
   state: "OPEN" → "COMMITTED"
   expiresAt: timestamp
   fromUid: original-owner
   toUid: new-owner
   ```

3. **`events/{eventId}`** - Check audit trail
   ```
   type: "TRANSFER"
   fromOwner: original-owner
   toOwner: new-owner
   timestamp: when-transferred
   ```

## 🔒 **Security Verification**

### **Firestore Rules Active**
- Direct token writes should be blocked
- Only current owner can create pending transfers
- All writes must go through Cloud Functions

### **Ownership History Protected**
- `previous_owners` array can only be appended to
- No modification of existing ownership history
- Complete provenance maintained

### **Atomic Transactions**
- Ownership changes happen in single transaction
- No intermediate states
- Either complete success or complete failure

## 🚀 **Performance Testing**

### **Concurrent Transfers**
- Multiple users trying to transfer same token
- Should prevent race conditions
- First successful transfer wins

### **Scale Testing**
- Multiple tokens transferring simultaneously
- Function cold starts
- Database transaction limits

## 🐛 **Troubleshooting**

### **Common Issues**

1. **Functions not found**
   ```bash
   firebase deploy --only functions
   ```

2. **Firestore rules blocking**
   ```bash
   firebase deploy --only firestore:rules
   ```

3. **Authentication issues**
   - Check Firebase Auth setup
   - Verify user permissions

4. **Flutter app errors**
   ```bash
   flutter clean && flutter pub get
   flutter run
   ```

### **Debug Commands**
```bash
# Check function status
firebase functions:list

# View real-time logs
firebase functions:log --follow

# Test functions directly
firebase functions:shell

# Check Firestore data
firebase firestore:delete tokens/test-token
```

## 📈 **Success Metrics**

### **Functional Tests Pass:**
- ✅ Owner can initiate transfers
- ✅ Receiver can complete transfers  
- ✅ Ownership changes atomically
- ✅ History is append-only
- ✅ Security rules enforced

### **Performance Acceptable:**
- ⚡ Transfer completion < 3 seconds
- ⚡ Function cold start < 5 seconds  
- ⚡ No failed transactions
- ⚡ Cleanup runs successfully

### **Security Verified:**
- 🔒 No unauthorized ownership changes
- 🔒 No history tampering possible
- 🔒 Race conditions prevented
- 🔒 Expired transfers cleaned up

## 🎯 **Next Steps After Testing**

1. **Production Deploy**: If tests pass, system is ready for production
2. **User Training**: Update documentation for users
3. **Monitoring Setup**: Configure alerts for function failures
4. **AES Integration**: Ready for cryptographic proof integration when needed

---

**🎉 The secure transfer system provides enterprise-grade security while maintaining the simple two-tap NFC experience!** 