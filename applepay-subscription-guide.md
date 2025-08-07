# Apple Pay & Subscription Implementation Guide

## Overview
This guide documents the complete implementation of Apple In-App Purchases (StoreKit) for Careguide's subscription model, including the once-per-day access control for basic users.

---

## Subscription Model

### **Pricing Structure**
- **Premium**: $8.99/month with 7-day free trial
- **Basic**: Free with once-per-day access limitation

### **Product Configuration**
- **App Store Product ID**: `1942`
- **App Store Subscription Name**: Careguide Monthly Premium
- **Internal App Name**: HealthGuide (development only)

### **Refund Policy** (Informational Only)
- Days 1-7: Free trial, cancel anytime
- Days 8-14: May be eligible for partial refund (handled by Apple)
- Days 15+: No refunds, access until end of billing period
- Apple controls all refunds - we cannot programmatically issue refunds

---

## Access Control Model

### **Premium Users**
- Unlimited app access
- All features enabled
- Cloud sync enabled
- Unlimited document storage
- Unlimited family members

### **Basic Users (Free)**
- **One app session per calendar day**
- Session starts on first app open of the day
- Can use all features except:
  - No document uploads/downloads
  - Limited to viewing existing documents
- Access resets at midnight local time

---

## Technical Architecture

### **Core Components**

1. **SubscriptionManager.swift**
   - Handles StoreKit purchases
   - Tracks subscription state
   - Manages trial periods
   - Product ID: `1942`

2. **AccessSessionManager.swift**
   - Enforces once-per-day access
   - Tracks user sessions
   - Handles edge cases (crashes, backgrounding)

3. **AccessSessionEntity (Core Data)**
   - Stores session history
   - Tracks usage patterns
   - Anti-gaming analytics

### **Access Control Flow**
```
App Launch
    ↓
Check Subscription Status
    ↓
Premium? → Full Access
    ↓ No (Basic User)
Check Today's Access
    ↓
Already Used? → Show Lock Screen with Countdown
    ↓ No
Grant Access → Start Session → Track Usage
```

### **Session Rules**
- Sessions tracked by calendar day (not 24-hour periods)
- Brief backgrounding (<5 minutes) doesn't end session
- Timezone changes handled gracefully
- Crashes don't count as session end

---

## Implementation Details

### **Core Data Schema**
```
AccessSessionEntity:
- id: UUID (indexed)
- userId: String
- accessDate: Date
- sessionStartTime: Date
- sessionEndTime: Date?
- isActive: Boolean
- accessType: Boolean (true = premium)
- featuresAccessed: String (JSON)
- medicationUpdatesCount: Int32
- documentsViewed: Int32
- [additional tracking fields]
```

### **Key Methods**
```swift
// Check if user can access today
AccessSessionManager.canAccessToday() -> Bool

// Start new session
AccessSessionManager.startDailySession()

// End current session
AccessSessionManager.endCurrentSession()

// Get time until next access
AccessSessionManager.timeUntilNextAccess() -> TimeInterval
```

---

## User Experience

### **First Launch (Basic User)**
```
"Welcome to Careguide!
You can access the app once per day.
Perfect for tracking medications at breakfast, lunch, or dinner.

[Start Today's Session] [Upgrade to Premium]"
```

### **Locked State (Already Accessed)**
```
"Daily Access Used
Come back tomorrow or upgrade for unlimited access

Next free access in: 14h 23m

[Upgrade to Premium - $8.99/mo]
[Why this limit?]"
```

### **Premium Benefits Display**
```
Premium Subscription
✓ Unlimited daily access
✓ Upload medical documents
✓ Advanced analytics
✓ Family sharing
✓ Cloud sync
✓ Priority support

7-day free trial, then $8.99/month
```

---

## Edge Cases Handled

1. **Time Zone Changes**
   - Access based on local calendar day
   - Traveling doesn't affect access

2. **Daylight Saving Time**
   - Calendar-based tracking unaffected
   - No "lost" or "extra" hours

3. **App Crashes**
   - Session continues if user returns within 5 minutes
   - Otherwise counts as session end

4. **Multiple Devices**
   - Sessions tracked per device
   - Future: CloudKit sync for unified tracking

5. **Date/Time Tampering**
   - Server time validation (future)
   - Reasonable limits on "future" dates

---

## Analytics & Anti-Gaming

### **Usage Patterns Tracked**
- Average session duration
- Features accessed per session
- Medication updates per session
- Upgrade prompt interactions

### **Suspicious Patterns**
- Very short sessions (<1 minute)
- Bulk operations (>10 medications in one session)
- Repeated subscribe/cancel cycles
- Time manipulation attempts

### **Response to Gaming**
- Show targeted upgrade prompts
- Limit bulk operations for repeat offenders
- Track but don't punish first-time users

---

## Testing Scenarios

### **StoreKit Testing**
1. New user → Free trial → Subscribe
2. Trial user → Cancel before charge
3. Subscriber → Cancel days 8-14
4. Subscriber → Cancel after day 15
5. Basic user → Daily access → Upgrade

### **Access Control Testing**
1. Basic user first access of day
2. Basic user second attempt same day
3. Access at 11:59 PM → 12:01 AM
4. App crash during session
5. Background for 3 min vs 10 min

---

## Migration & Rollout

### **Phase 1: Core Implementation**
- AccessSessionManager
- Basic access control
- Lock screen UI

### **Phase 2: Enhanced Features**
- Analytics tracking
- Anti-gaming measures
- Improved upgrade prompts

### **Phase 3: Server Integration**
- Server time validation
- Cross-device sync
- Advanced analytics

---

## Compliance Notes

### **Apple Requirements**
- ✅ Using StoreKit for digital subscriptions
- ✅ No external payment processors
- ✅ Clear subscription terms displayed
- ✅ Easy cancellation (via Settings)
- ✅ Restore purchases supported

### **Disabled Features**
- ❌ Stripe integration (commented out)
- ❌ Custom refund handling
- ❌ External payment links

---

## Support & Troubleshooting

### **Common Issues**
1. "I can't access the app"
   - Check if already used today
   - Verify timezone settings
   - Try force-quit and reopen

2. "My subscription isn't recognized"
   - Restore purchases
   - Check Apple ID
   - Verify payment processed

3. "Lost access after traveling"
   - Timezone-based access
   - Wait until local midnight

### **Debug Information**
- Session ID
- Last access timestamp
- Current subscription status
- Device timezone
- App version

---

## Future Enhancements

1. **Web Portal**
   - Stripe payments allowed
   - Sync with iOS app
   - Full feature access

2. **Family Plan**
   - Shared subscription
   - Multiple device access
   - Centralized billing

3. **Annual Plan**
   - Discounted yearly option
   - Better retention
   - Higher LTV

---

## Revenue Optimization

### **Upgrade Prompts**
- After trying locked features
- At session end for engaged users
- When viewing premium features
- Time-sensitive offers

### **Retention Strategies**
- Progressive benefits
- Streak tracking
- Engagement rewards
- Win-back campaigns

---

## Conclusion

This implementation balances:
- **User Value**: Free tier provides real utility
- **Revenue**: Clear premium benefits drive upgrades
- **Simplicity**: Easy to understand model
- **Compliance**: Fully Apple-compliant

The once-per-day model creates natural upgrade moments while respecting users who need basic medication tracking.