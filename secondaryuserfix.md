# Secondary User Real-time Data Fix

## Current Status (Working ✅)

### What's Working:
1. **Primary User Flow**: 
   - Creates groups successfully
   - Adds medications/supplements to Firebase group space (`/groups/{groupId}/medications/`)
   - Data persists and syncs correctly
   - Can delete old groups when creating new ones

2. **Firebase Structure**:
   - Groups are properly created with correct permissions
   - Data is stored in group-centric architecture
   - Security rules are working correctly with delete permissions

3. **Secondary User Join**:
   - Can join groups with invite code
   - Gets added to `memberIds` and `writePermissionIds`
   - Group is saved to UserDefaults

### What's NOT Working:
- **Secondary user's dashboard shows Core Data (empty) instead of Firebase data**
- Dashboard loads before group is set, uses Core Data, and never refreshes

## The Problem

The issue occurs in this sequence:
1. Secondary user opens app → No group in UserDefaults
2. Dashboard loads → Checks `FirebaseGroupService.shared.currentGroup` → It's `nil`
3. Dashboard uses Core Data (local mode) → Shows 0 items
4. User joins group → Group is now set
5. **Dashboard doesn't refresh** → Still showing Core Data

The key code in `HealthDataProcessor.swift` (line 40):
```swift
if FirebaseGroupService.shared.currentGroup != nil {
    // Fetch from Firebase
} else {
    // Fetch from Core Data (THIS IS WHAT HAPPENS)
}
```

## Best Fix: Make Dashboard Reactive to Group Changes

### Step 1: Add Group Change Notification

In `FirebaseGroupService.swift`, add a notification when group changes:

**After line 41 (in the `currentGroup` didSet):**
```swift
// Notify that group has changed
NotificationCenter.default.post(
    name: .firebaseGroupDidChange,
    object: nil,
    userInfo: ["groupId": group.id]
)
```

**Add notification name extension at the end of file:**
```swift
extension Notification.Name {
    static let firebaseGroupDidChange = Notification.Name("firebaseGroupDidChange")
}
```

### Step 2: Make Dashboard Listen for Group Changes

In `MyHealthDashboardView.swift`:

**Replace the current `.task` block (around line 68-79) with:**
```swift
.task {
    // Load data on first appear
    await loadDataIfNeeded()
}
.onReceive(NotificationCenter.default.publisher(for: .firebaseGroupDidChange)) { _ in
    Task {
        print("📱 Group changed - reloading dashboard data")
        hasLoadedData = false  // Force reload
        await viewModel.loadData()
        hasLoadedData = true
    }
}
```

**Add this helper function after body:**
```swift
private func loadDataIfNeeded() async {
    guard !hasLoadedData else { 
        return 
    }
    
    print("🔍 DEBUG: MyHealthDashboardView loading data...")
    print("   Current group: \(FirebaseGroupService.shared.currentGroup?.name ?? "NO GROUP")")
    
    await viewModel.loadData()
    selectedPeriods = [viewModel.currentPeriod]
    hasLoadedData = true
    
    print("🔍 DEBUG: Loaded \(viewModel.allItems.count) items")
    
    // Update badge and notifications as before
    await BadgeManager.shared.updateBadgeForCurrentPeriod()
    
    if viewModel.allItems.count > 0 {
        hasHealthItems = true
        // Notification setup code...
    }
}
```

### Step 3: Ensure Group Loads on App Start

In `FirebaseGroupService.swift`, the `loadSavedGroup()` already calls `findUserGroups()` which will:
1. Search for groups where user is a member
2. Auto-load the first group found
3. This triggers the notification
4. Dashboard refreshes with Firebase data

### Step 4: Force Refresh After Join (Backup)

In `GroupDashboardView.swift`, after successful join (around line 85):
```swift
.onChange(of: viewModel.activeGroupId) { _, newValue in
    if newValue != nil {
        // Force dashboard refresh when group becomes active
        NotificationCenter.default.post(
            name: .firebaseGroupDidChange,
            object: nil
        )
    }
}
```

## Expected Behavior After Fix:

1. **Secondary User First Launch**:
   - App starts → No saved group
   - `findUserGroups()` runs → Finds user is member of "Sample only"
   - Auto-loads group → Sets `currentGroup`
   - Posts notification → Dashboard refreshes
   - Shows medications from Firebase

2. **Secondary User Joins New Group**:
   - Joins with invite code
   - Group is set → Posts notification
   - Dashboard immediately refreshes
   - Shows all group medications

3. **App Restart**:
   - Group ID in UserDefaults
   - Loads saved group
   - Dashboard uses Firebase from start

## Testing Steps:

1. Apply the fixes above
2. On secondary device:
   - Delete app to clear all data
   - Reinstall and launch
   - Join with invite code
   - Should immediately see medications

3. Force quit and restart:
   - Should still see medications (persisted group)

## What We're NOT Changing:

- Firebase data structure (working perfectly)
- Group creation/deletion logic (working)
- Security rules (working)
- Primary user flow (working)
- Write permissions model (working)

## Alternative Quick Fix (If Needed):

If the reactive approach has issues, a simpler fix is to add a "Refresh" button:

In `MyHealthDashboardView.swift` toolbar:
```swift
ToolbarItem(placement: .navigationBarLeading) {
    Button("Refresh") {
        Task {
            hasLoadedData = false
            await viewModel.loadData()
            hasLoadedData = true
        }
    }
}
```

This lets users manually refresh after joining a group.

## Notes:

- The medications ARE in Firebase (verified in screenshots)
- The group IS properly joined (verified in logs)
- This is purely a UI refresh issue
- The fix makes the UI reactive to group changes
- No changes to data layer needed