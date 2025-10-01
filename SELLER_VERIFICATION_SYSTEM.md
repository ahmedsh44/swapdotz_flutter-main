# SwapDotz Seller Verification System

## Overview

The seller verification system ensures authentic transactions by requiring sellers to physically verify ownership with NFC scanning. The **30-day verification window** serves dual purposes: allowing time for NFC verification AND covering the entire shipping/delivery period.

## How It Works

### 1. **Payment Triggers Verification Session**
- When a buyer completes payment for a SwapDot
- A **30-Day Verification Session** is created
- This window covers both verification AND shipping time
- Seller gets notified they need to verify ownership

### 2. **NFC Verification (Immediate)**
- Seller must physically scan the SwapDot with their device
- NFC scan verifies they actually have the token
- System checks the scanned ID matches the sold token
- Only the current owner can successfully verify

### 3. **Shipping & Delivery Period**
- After NFC verification, seller ships the physical SwapDot
- **30-day window covers entire shipping period**
- Allows time for international shipping, customs, delays
- Seller marks transaction complete when buyer confirms receipt

### 4. **Final Ownership Transfer & Payment Release**
- Buyer confirms receipt and takes digital ownership
- **Only then** does payment release to seller (minus 5% platform fee)
- Seller funds are held until buyer confirms receipt
- Physical and digital ownership transfer together
- Transaction marked as completed

## 30-Day Window: Dual Purpose

### 🔍 **Verification Time (1-7 days typically)**
- Seller scans SwapDot with NFC to prove ownership
- Quick verification process (minutes once started)
- Allows flexibility for seller availability

### 📦 **Shipping Time (1-30 days total)**
- **Domestic shipping**: 2-7 days
- **International shipping**: 7-21 days
- **Express shipping**: 1-3 days
- **Customs delays**: Additional 1-14 days
- **Rural delivery**: Additional 1-7 days

### ⏰ **Timeline Examples**

#### Domestic Sale (USA)
```
Day 1: Payment → Verification session created
Day 2: Seller scans NFC → Ships via USPS Priority
Day 5: Buyer receives → Takes ownership → Seller gets paid
```

#### International Sale (USA → Europe)
```
Day 1: Payment → Verification session created
Day 3: Seller scans NFC → Ships via FedEx International
Day 12: Customs processing
Day 18: Buyer receives → Takes ownership → Seller gets paid
```

#### Worst Case Scenario
```
Day 1: Payment → Verification session created
Day 7: Seller finally scans NFC (was traveling)
Day 10: Ships standard international mail
Day 25: Package arrives after delays
Day 27: Buyer takes ownership → Seller gets paid
```

## Security Benefits

### ✅ **Fraud Prevention**
- **Physical verification**: Must actually possess the SwapDot
- **No fake listings**: Can't sell SwapDotz you don't own
- **Shipping proof**: Digital transfer only after physical delivery

### ✅ **Buyer Protection**
- **30-day guarantee**: If no verification/delivery, automatic refund
- **Held payment**: Seller can't access funds until completion
- **Dispute resolution**: Clear timeline for support escalation

### ✅ **Seller Protection**
- **Payment security**: Funds guaranteed after buyer takes ownership
- **Shipping flexibility**: 30 days handles any shipping method
- **International sales**: Sufficient time for customs/delays

## User Experience

### For Sellers
1. **List SwapDot** → Only owned tokens appear
2. **Receive Payment** → 30-day verification window starts
3. **Scan to Verify** → NFC scan proves ownership (do this quickly!)
4. **Ship SwapDot** → Send physical token to buyer
5. **Get Paid** → Funds release when buyer takes ownership

### For Buyers
1. **Find SwapDot** → Browse verified listings
2. **Make Payment** → Secure payment via Stripe
3. **Wait for Shipping** → Seller has 30 days total
4. **Receive Package** → Physical SwapDot arrives
5. **Take Ownership** → Confirm receipt and take digital ownership

## Business Logic

### Why 30 Days?

#### **Shipping Realities**
- **Standard international**: 7-21 days
- **Customs processing**: 1-14 days additional
- **Rural/remote delivery**: 1-7 days additional
- **Holiday delays**: 2-10 days additional
- **Weather/logistics issues**: 1-7 days additional

#### **User Flexibility**
- **Seller travel**: May need time to access SwapDot
- **Buyer availability**: May be traveling when package arrives
- **Communication**: Time to resolve shipping issues

#### **Platform Protection**
- **Dispute resolution**: Time for customer support
- **Fraud investigation**: Time to verify suspicious activity
- **Payment processing**: Time for payment settlement

### Edge Cases Handled

#### **Seller Issues**
- **Lost SwapDot**: Can cancel with buyer refund
- **Damaged in shipping**: Insurance claims and refunds
- **Can't access token**: 30 days allows problem solving

#### **Buyer Issues**
- **Wrong address**: Time to redirect shipping
- **Package stolen**: Time for shipping insurance claims
- **Buyer traveling**: Flexible completion timing

#### **System Issues**
- **NFC problems**: Support can manually verify
- **Shipping delays**: 30 days accommodates most issues
- **Communication gaps**: Time for resolution

## Implementation Notes

### Status Progression
```
pending_nfc_scan → nfc_verified → completed
     ↓                ↓             ↓
  Day 1-30         Day 1-30    Final Transfer
```

### Key Timestamps
- `created_at`: Payment received, session started
- `nfc_verified_at`: Seller completed ownership verification
- `completed_at`: Final transaction completion
- `expires_at`: 30 days from creation (automatic refund)

### Notifications
- **Day 1**: "Payment received! Please verify ownership with NFC"
- **Day 7**: "Reminder: Please verify your SwapDot ownership"
- **Day 21**: "Action needed: 9 days remaining to complete sale"
- **Day 28**: "Urgent: 2 days remaining before automatic refund"

## Benefits Summary

### 🛡️ **Security & Trust**
- Physical verification prevents fraud
- Shipping time coverage builds buyer confidence
- Clear timelines set proper expectations

### 💰 **Financial Protection**
- Automatic refunds protect buyers
- Held payments protect transaction integrity
- Platform fees only on completed sales

### 🌍 **Global Commerce**
- International shipping support
- Customs delay accommodation
- Multiple shipping method compatibility

### 📈 **Platform Quality**
- Higher completion rates due to adequate time
- Fewer disputes due to clear timelines
- Better seller/buyer satisfaction

---

**Result**: A marketplace that handles the realities of global physical shipping while maintaining security through NFC verification. The 30-day window ensures both verification completion and successful delivery worldwide. 