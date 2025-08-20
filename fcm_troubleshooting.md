# FCM Notification Troubleshooting Guide

## Problem: Parent clicks "I ate" button but child app doesn't receive notification

## Root Cause Analysis

### 1. Firebase Security Rules Issue ⚠️
**MAIN PROBLEM**: Firebase Security Rules are blocking child app from writing FCM tokens.

**Error seen**: `[cloud_firestore/permission-denied] Missing or insufficient permissions`

**Fix**: Deploy proper security rules that allow `child_devices` subcollection writes.

### 2. FCM Token Registration Failure 🔧
Due to security rules, child app FCM tokens are not reaching Firebase, so parent app has no tokens to send notifications to.

## URGENT FIXES NEEDED:

### Step 1: Fix Firebase Security Rules
1. Go to Firebase Console: https://console.firebase.google.com/
2. Select project: `thanks-everyday`
3. Go to Firestore Database → Rules
4. Replace existing rules with the rules from `firestore_fcm_rules.txt`
5. Click "Publish"

### Step 2: Test FCM Token Registration
1. After deploying rules, use the "🔧 알림 등록 (디버그)" button
2. Should see in terminal logs:
   ```
   🔥 FIREBASE: Attempting to write to families/{familyId}/child_devices/{deviceId}
   🔥 FIREBASE: Successfully wrote FCM token to Firestore
   ✅ FCM token registered successfully to Firestore
   ```
3. Check Firebase Console → Firestore → families/{familyId}/child_devices/ should have documents

### Step 3: Verify Parent App Configuration
Parent app needs to:
1. Read child FCM tokens from `families/{familyId}/child_devices/`
2. Send notifications to those tokens when "I ate" is clicked
3. Use proper FCM server key or service account

### Step 4: Check Firebase Logs
Terminal should show when notifications are received:
```
🔥 FIREBASE: Received foreground message: {messageId}
🔥 FIREBASE: Title: {title}
🔥 FIREBASE: Body: {body}
```

## Current Status:
- ✅ Child app: FCM token generation working
- ✅ Child app: Authentication working  
- ✅ Child app: Family connection working
- ❌ Child app: FCM token registration BLOCKED by security rules
- ❌ Parent app: Cannot read child FCM tokens (none exist)
- ❌ Notifications: Not working because no registered tokens

## Next Steps:
1. **PRIORITY 1**: Deploy Firebase security rules
2. **PRIORITY 2**: Test FCM token registration
3. **PRIORITY 3**: Verify parent app sends to registered tokens
4. **PRIORITY 4**: Test end-to-end notification flow

Once security rules are fixed, notifications should work immediately.