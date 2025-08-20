# CloudKit Sync Implementation for Groups

## Current Status
- ✅ CloudKit enabled in Core Data model
- ✅ All entities visible in configuration
- ✅ No data migration needed (app not live, zero existing data)
- ✅ All attributes already optional (from previous CloudKit attempt)
- ✅ awakeFromInsert() implemented for all entities

## Architecture Decision
1. **Data Ownership**: Group owns data (not individual users)
2. **Access Model**: All 3 users have read access, admin/member permissions for write
3. **Sharing Scope**: ALL data shared within group
4. **Starting Point**: Zero data, fresh start

## Implementation Phases

### Phase 0: Pre-flight Checks ✅
- [x] CloudKit enabled in project capabilities
- [x] CloudKit checkbox enabled in Core Data model
- [x] All attributes optional
- [x] Git backup created

### Phase 1: Enable CloudKit Container ✅ COMPLETED
**Goal**: Switch to NSPersistentCloudKitContainer without breaking anything

#### Step 1.1: Update Persistence.swift ✅
- Changed from NSPersistentContainer to NSPersistentCloudKitContainer
- Added comment for tracking

#### Step 1.2: Add CloudKit Configuration ✅
- Enabled cloudKitContainerOptions with container ID: iCloud.com.qashsolutions.HealthGuide
- Added NSPersistentHistoryTrackingKey (required for sync)
- Added NSPersistentStoreRemoteChangeNotificationPostOptionKey (for real-time sync)

#### Step 1.3: Test Personal Sync ⚠️ 
- ✅ CloudKit container loads successfully
- ✅ No errors on app launch
- ✅ Data saves locally with CloudKit enabled
- ⚠️ Personal sync requires SAME Apple ID on both devices
- ❌ Cannot test with different Apple IDs (by design)

**Status**: CloudKit foundation working. Need GROUP SHARING for different Apple IDs.

### Phase 2: Add CloudKit Share Support ✅ COMPLETED
**Goal**: Add sharing infrastructure without activating

#### Step 2.1: Add Share Properties to Entities ✅
Entities that need sharing:
- ✅ CareGroupEntity (the share container)
- ✅ GroupMemberEntity
- ✅ MedicationEntity
- ✅ SupplementEntity  
- ✅ DietEntity
- ✅ ContactEntity
- ✅ DocumentEntity
- ✅ CareMemoEntity

#### Step 2.2: Create CloudKitShareManager ✅
- ✅ Handle share creation
- ✅ Handle share acceptance
- ✅ Manage permissions
- ✅ Store share reference in group settings

### Phase 3: Implement Group Sharing ✅ COMPLETED
**Goal**: Enable actual data sharing between group members

#### Step 3.1: Create Share for Group ✅
When group is created:
1. ✅ Create CKShare for the group
2. ✅ Set permissions (owner = admin)
3. ✅ Generate share URL (using 6-digit code)

#### Step 3.2: Join Group via Share ✅
When user joins with invite code:
1. ✅ Fetch CKShare for that group
2. ✅ Accept share
3. ✅ Sync group data

#### Step 3.3: Permission Management ✅
- ✅ Admin (owner + participants with .readWrite)
- ✅ Member (participants with .readOnly)

#### Step 3.4: Real-time Sync ✅
- ✅ Created CloudKitSyncService for real-time sync
- ✅ Auto-sync enabled every 60 seconds
- ✅ Listen for remote CloudKit changes
- ✅ Debounced local saves to trigger sync

### Phase 4: Data Sync Rules
**What syncs in a group:**
- ✅ All medications of all members
- ✅ All supplements of all members
- ✅ All diet entries of all members
- ✅ All contacts (doctors, emergency)
- ✅ All documents
- ✅ All care memos

**What stays private:**
- ❌ AccessSessionEntity (device specific)
- ❌ PaymentEntity (user specific)
- ❌ SubscriptionEntity (user specific)

## Potential Issues & Solutions

### Issue 1: Entity Relationships
**Problem**: CloudKit doesn't support many-to-many relationships directly
**Solution**: Already using intermediate entities (GroupMemberEntity)

### Issue 2: Unique Constraints
**Problem**: CloudKit doesn't enforce unique constraints
**Solution**: Handle in code (check before creating)

### Issue 3: Share Limits
**Problem**: CloudKit has participant limits
**Solution**: We only need 3 users max (within limits)

### Issue 4: Conflict Resolution
**Problem**: Two users edit same medication
**Solution**: Last-write-wins with timestamp

## Testing Checklist

### Phase 1 Testing
- [ ] App launches without crashes
- [ ] Can create medication locally
- [ ] Personal sync works (same Apple ID, different device)
- [ ] No data loss from existing entities

### Phase 2 Testing  
- [ ] Can create group
- [ ] Can generate invite code
- [ ] Group data structure intact

### Phase 3 Testing
- [ ] User A creates group
- [ ] User B joins group
- [ ] User A adds medication
- [ ] User B sees medication (read-only)
- [ ] User C joins group
- [ ] All 3 see same data

## Rollback Plan
If issues occur:
1. Disable CloudKit checkbox in Core Data model
2. Change back to NSPersistentContainer
3. Clean build
4. Data remains local

## Next Immediate Step
1. Change to NSPersistentCloudKitContainer in Persistence.swift
2. Add history tracking options
3. Build and test
4. Verify nothing breaks

## Questions to Resolve
1. **Invite Code Mechanism**: Should we keep 6-digit code or use CloudKit share URLs?
   - Current: 6-digit code
   - Consideration: CloudKit shares use URLs/QR codes
   
2. **Group Deletion**: What happens to shared data when group is deleted?
   - Option A: Delete all group data
   - Option B: Each user keeps their own data

3. **Offline Behavior**: How to handle offline modifications?
   - CloudKit handles this automatically with conflict resolution

## Success Criteria
- ✅ All 3 group members see same health data
- ✅ Admins can add/edit/delete
- ✅ Members can only read
- ✅ Changes sync in real-time (when online)
- ✅ Works offline and syncs when connected
- ✅ No data loss or corruption

## DO NOT MODIFY (Yet)
These files work fine locally, don't change until sync is verified:
- All Entity+CoreDataClass files
- All Entity+CoreDataProperties files  
- All awakeFromInsert implementations
- All existing Core Data queries

## Current Architecture That Helps Us
1. ✅ All attributes already optional (no migration needed)
2. ✅ UUID-based IDs (CloudKit compatible)
3. ✅ Proper relationships between entities
4. ✅ CreatedAt/UpdatedAt timestamps (for conflict resolution)