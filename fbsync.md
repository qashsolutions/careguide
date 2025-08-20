# Firebase Migration Plan - HealthGuide
## Complete Core Data to Firebase Migration

---

## 🎯 Migration Overview

### Current State
- **16 Core Data Entities** storing user health data
- **Complex relationships** between medications, doses, and schedules  
- **File storage** for documents and audio memos
- **Multi-user groups** with permission system
- **Threading issues** between Core Data and Firebase sync

### Target State
- **Firebase Firestore** as single source of truth
- **Real-time sync** between 3 caregivers
- **Firebase Storage** for documents and audio
- **Offline persistence** with Firebase SDK
- **Zero sync conflicts** - no Core Data

---

## 📊 Core Data Entities to Migrate

### Priority 1: Core Health Data (Day 1)
| Entity | Firebase Collection | User Data | Notes |
|--------|-------------------|-----------|--------|
| MedicationEntity | `/medications/{medId}` | YES | Core functionality |
| SupplementEntity | `/supplements/{supId}` | YES | Similar to medications |
| DietEntity | `/diets/{dietId}` | YES | Meal tracking |
| DoseEntity | `/doses/{doseId}` | YES | Tracks taken/missed |
| ScheduleEntity | `/schedules/{schedId}` | YES | Complex scheduling logic |

### Priority 2: Group & Collaboration (Day 1)
| Entity | Firebase Collection | User Data | Notes |
|--------|-------------------|-----------|--------|
| CareGroupEntity | `/groups/{groupId}` | YES | Already partially in Firebase |
| GroupMemberEntity | `/groups/{groupId}/members/{memberId}` | YES | Permissions system |

### Priority 3: User Content (Day 2)
| Entity | Firebase Collection | User Data | Notes |
|--------|-------------------|-----------|--------|
| DocumentEntity | `/documents/{docId}` | YES | Needs Firebase Storage |
| DocumentCategoryEntity | `/documentCategories/{catId}` | YES | Organization |
| ContactEntity | `/contacts/{contactId}` | YES | Healthcare providers |
| CareMemoEntity | `/memos/{memoId}` | YES | Audio files → Storage |
| ConflictEntity | `/conflicts/{conflictId}` | YES | Drug interactions |

### Priority 4: Analytics (Optional)
| Entity | Firebase Collection | User Data | Notes |
|--------|-------------------|-----------|--------|
| AccessSessionEntity | `/sessions/{sessionId}` | Analytics | Could use Firebase Analytics |
| SubscriptionEntity | `/subscriptions/{subId}` | Business | Stripe integration |
| PaymentEntity | `/payments/{paymentId}` | Business | Payment history |
| RefundEntity | `/refunds/{refundId}` | Business | Refund tracking |

---

## 🏗️ Migration Architecture

### Phase 1: Data Models (4 hours)
```swift
// Before (Core Data)
class MedicationEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var dosage: String
    // Complex Core Data relationships
}

// After (Firebase)
struct FirestoreMedication: Codable {
    let id: String
    let name: String
    let dosage: String
    let groupId: String  // For group sharing
    let createdBy: String  // User who created
    let updatedAt: Timestamp
}
```

### Phase 2: Service Layer (4 hours)
```swift
// New unified service
class FirebaseHealthService {
    // Medications
    func saveMedication(_ med: Medication, groupId: String) async throws
    func observeMedications(groupId: String) -> AsyncStream<[Medication]>
    
    // Doses
    func markDoseTaken(doseId: String) async throws
    func observeTodaysDoses(groupId: String) -> AsyncStream<[Dose]>
    
    // Real-time sync for all 3 caregivers!
}
```

### Phase 3: UI Updates (2 hours)
- Replace `@FetchRequest` with Firebase listeners
- Update ViewModels to use `FirebaseHealthService`
- Remove Core Data dependencies from views

---

## 🔄 Real-time Sync Implementation

### Medication Sync Example
```swift
// Caregiver 1 adds medication
func addMedication() async {
    let med = FirestoreMedication(
        id: UUID().uuidString,
        name: "Aspirin",
        dosage: "81mg",
        groupId: currentGroup.id,
        createdBy: currentUser.id
    )
    
    try await db.collection("groups")
        .document(groupId)
        .collection("medications")
        .document(med.id)
        .setData(med)
}

// Caregivers 2 & 3 see it instantly
func observeMedications() {
    db.collection("groups")
        .document(groupId)
        .collection("medications")
        .addSnapshotListener { snapshot, error in
            // UI updates immediately!
        }
}
```

---

## 🗂️ Firebase Collection Structure

```
firestore-root/
├── groups/
│   └── {groupId}/
│       ├── info (name, settings, inviteCode)
│       ├── members/
│       │   └── {userId}/ (name, role, permissions)
│       ├── medications/
│       │   └── {medId}/ (name, dosage, schedule)
│       ├── supplements/
│       │   └── {supId}/ (name, dosage, schedule)
│       ├── doses/
│       │   └── {doseId}/ (medId, scheduledTime, taken)
│       ├── documents/
│       │   └── {docId}/ (name, url, category)
│       └── memos/
│           └── {memoId}/ (title, audioUrl, transcript)
├── users/
│   └── {userId}/
│       ├── profile (name, email, settings)
│       └── groups (array of groupIds)
└── inviteCodes/
    └── {code}/ (groupId, createdAt)
```

---

## 📱 Offline Support

```swift
// Enable offline persistence
let settings = FirestoreSettings()
settings.isPersistenceEnabled = true
settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
db.settings = settings

// Works offline automatically!
// Changes sync when back online
```

---

## 🚀 Implementation Steps

### Day 1 Morning: Core Models (4 hours)
1. ✅ Create Firestore models for medications, supplements, doses
2. ✅ Create FirebaseHealthService with CRUD operations
3. ✅ Test basic save/fetch operations

### Day 1 Afternoon: Real-time Sync (4 hours)
1. ✅ Implement real-time listeners for medications
2. ✅ Add dose tracking with instant updates
3. ✅ Test with 3 simultaneous users

### Day 2 Morning: Content Migration (3 hours)
1. ✅ Migrate documents to Firebase Storage
2. ✅ Migrate audio memos with transcriptions
3. ✅ Implement contacts sync

### Day 2 Afternoon: Polish & Testing (3 hours)
1. ✅ Remove all Core Data dependencies
2. ✅ Test offline mode
3. ✅ Multi-user testing with your caregivers

---

## 🎯 Success Metrics

### What Your 3 Caregivers Will Experience:
- **Mom adds medication** → Dad & Sister see it instantly ✅
- **Dad marks dose taken** → Mom sees compliance immediately ✅
- **Sister uploads document** → All can access instantly ✅
- **Works offline** → Syncs when connection returns ✅
- **No sync conflicts** → Single source of truth ✅

---

## ⚠️ Migration Considerations

### Existing User Data
- Need one-time migration script for existing Core Data
- Estimate: ~2 hours to write migration tool
- Run once per device during update

### File Storage
- Documents and audio currently in local storage
- Need to upload to Firebase Storage during migration
- Keep local cache for offline access

### User IDs
- Currently using device UUIDs
- Already have Firebase anonymous auth
- Map device IDs to Firebase user IDs

---

## 🔥 Why This Will Work

1. **Proven Pattern**: Firebase + Firestore is battle-tested for real-time apps
2. **Simple Architecture**: One data source = no sync issues
3. **Built for Collaboration**: Firebase designed for multi-user apps
4. **Offline First**: Works without internet, syncs when connected
5. **Cross-Platform**: Same code works on iOS and Android

---

## 📝 Code to Remove

### Core Data Files to Delete:
- `CoreDataManager.swift` and all extensions
- `PersistenceController.swift`
- `Persistence.swift`
- All `*Entity+CoreDataClass.swift` files
- All `*Entity+CoreDataProperties.swift` files
- `HealthDataModel.xcdatamodeld`
- `CloudKitSyncService.swift`
- `CloudKitShareManager.swift`

### Dependencies to Remove:
- `import CoreData` statements
- `@FetchRequest` property wrappers
- `NSManagedObjectContext` environment values
- `NSPersistentCloudKitContainer` references

---

## 🎉 End Result

A **clean, simple, real-time** health management app where:
- 3 caregivers share everything instantly
- No sync conflicts possible
- Works offline
- Simpler codebase
- Ready for Android expansion

**Total Implementation Time: 14-16 hours**

---

## Ready to Start?

Let's begin with Phase 1: Converting Core Data models to Firebase models. The threading nightmare will be over, and your caregivers will have the real-time collaboration they need!