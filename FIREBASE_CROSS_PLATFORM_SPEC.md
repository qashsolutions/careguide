# Firebase Cross-Platform Specification
## For iOS and Android Compatibility

### Overview
This document defines the Firebase Firestore structure that MUST be followed by both iOS and Android apps to ensure seamless data sharing between platforms.

### Table of Contents
1. [Authentication](#authentication)
2. [Data Structure](#data-structure)
3. [Permission Model](#permission-model)
4. [API Operations](#api-operations)
5. [Error Handling](#error-handling)
6. [Real-time Sync](#real-time-sync)
7. [Edge Cases](#edge-cases)
8. [Testing](#testing)

---

## Authentication

### Firebase Anonymous Authentication
```kotlin
// Android Example
FirebaseAuth.getInstance().signInAnonymously()
    .addOnSuccessListener { authResult ->
        val userId = authResult.user?.uid // Use this for all operations
    }
```

```swift
// iOS Example
Auth.auth().signInAnonymously { authResult, error in
    let userId = authResult?.user.uid // Use this for all operations
}
```

**Important**: 
- User ID persists until app uninstall
- After reinstall, new anonymous user is created
- Store critical data in Firebase, not locally

---

## Data Structure

### 1. Personal Data Collections
All user data is primarily stored in their personal space:

```
/users/{userId}/
  ├── medications/
  │   └── {medicationId}/
  ├── supplements/
  │   └── {supplementId}/
  ├── diets/
  │   └── {dietId}/
  ├── doses/
  │   └── {doseId}/
  └── schedules/
      └── {scheduleId}/
```

### 2. Groups Collection
```
/groups/{groupId}/
  ├── Document fields:
  │   ├── id: String (UUID format: "550e8400-e29b-41d4-a716-446655440000")
  │   ├── name: String (max 50 chars)
  │   ├── inviteCode: String (exactly 6 chars, uppercase alphanumeric)
  │   ├── createdBy: String (Firebase userId)
  │   ├── adminIds: String[] (array of userIds)
  │   ├── memberIds: String[] (array of userIds, MUST enforce max 3)
  │   ├── writePermissionIds: String[] (array of userIds)
  │   ├── createdAt: Timestamp (Firebase server timestamp)
  │   └── updatedAt: Timestamp (Firebase server timestamp)
  │
  ├── members/{memberId}/
  │   ├── id: String (UUID format)
  │   ├── userId: String (Firebase auth UID)
  │   ├── groupId: String (parent group ID)
  │   ├── name: String (display name, max 50 chars)
  │   ├── role: String (ONLY "admin" OR "member", no other values)
  │   ├── permissions: String (ONLY "write" OR "read", no other values)
  │   ├── joinedAt: Timestamp
  │   └── lastActiveAt: Timestamp (nullable)
  │
  ├── member_medications/{userId_medicationId}/
  │   ├── userId: String
  │   ├── medicationId: String
  │   ├── personalDataPath: String (format: "users/{userId}/medications/{medicationId}")
  │   └── updatedAt: Timestamp
  │
  ├── member_supplements/{userId_supplementId}/
  │   └── (same structure as member_medications)
  │
  └── member_diets/{userId_dietId}/
      └── (same structure as member_medications)
```

### 3. Medication Document Structure
```javascript
{
  "id": "550e8400-e29b-41d4-a716-446655440000",  // UUID as string
  "groupId": "groupId or userId",  // For personal space, use userId
  "name": "Aspirin",               // Required, max 100 chars
  "dosage": "500mg",               // Required, format: number + unit
  "quantity": 1,                   // Required, Integer, min: 1
  "unit": "tablet",                // Required, enum values below
  "notes": "Take with food",      // Optional, max 500 chars
  "isActive": true,                // Required, Boolean
  "category": "painkiller",        // Optional, enum values below
  "prescribedBy": "Dr. Smith",    // Optional, max 100 chars
  "prescriptionNumber": "RX12345", // Optional, max 50 chars
  "refillsRemaining": 3,          // Optional, Integer, min: 0
  "expirationDate": Timestamp,    // Optional
  "createdBy": "userId",          // Required, Firebase userId
  "createdAt": Timestamp,         // Required, server timestamp
  "updatedAt": Timestamp,         // Required, server timestamp
  "scheduleId": "scheduleId"      // Optional, reference
}
```

#### Unit Enum Values:
- "tablet", "capsule", "ml", "mg", "g", "oz", "tsp", "tbsp", "drops", "puffs", "patches", "injections"

#### Category Enum Values:
- "painkiller", "antibiotic", "vitamin", "blood_pressure", "diabetes", "heart", "cholesterol", "other"

### 4. Supplement Document Structure
```javascript
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "groupId": "groupId or userId",
  "name": "Vitamin D",            // Required, max 100 chars
  "dosage": "1000IU",             // Required
  "unit": "capsule",              // Required, use same enum as medication
  "quantity": 1,                  // Required, Integer, min: 1
  "notes": "Take in morning",     // Optional, max 500 chars
  "isActive": true,               // Required
  "category": "vitamin",          // Optional, enum values below
  "brand": "Nature's Way",        // Optional, max 50 chars
  "purpose": "Bone health",       // Optional, max 200 chars
  "interactions": "None known",   // Optional, max 500 chars
  "createdBy": "userId",          // Required
  "createdAt": Timestamp,         // Required
  "updatedAt": Timestamp,         // Required
  "scheduleId": "scheduleId"      // Optional
}
```

#### Supplement Category Enum Values:
- "vitamin", "mineral", "herbal", "probiotic", "omega3", "protein", "other"

### 5. Diet Document Structure
```javascript
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "groupId": "groupId or userId",
  "name": "Oatmeal",              // Required, max 100 chars
  "portion": "1 cup",             // Required, max 50 chars
  "notes": "With berries",        // Optional, max 500 chars
  "isActive": true,               // Required
  "category": "breakfast",        // Optional, enum values below
  "calories": 150,                // Optional, Integer, min: 0
  "restrictions": ["gluten_free"], // Optional, Array of strings
  "mealType": "breakfast",        // Optional, enum values below
  "createdBy": "userId",          // Required
  "createdAt": Timestamp,         // Required
  "updatedAt": Timestamp,         // Required
  "scheduleId": "scheduleId"      // Optional
}
```

#### Diet Category/MealType Enum Values:
- "breakfast", "lunch", "dinner", "snack", "beverage"

#### Dietary Restrictions Enum Values:
- "gluten_free", "dairy_free", "vegan", "vegetarian", "nut_free", "low_sodium", "diabetic", "low_carb", "kosher", "halal"

### 6. Schedule Document Structure
```javascript
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "groupId": "groupId or userId",
  "frequency": "daily",           // Required, enum: "daily", "weekly", "custom"
  "timePeriods": ["morning", "evening"], // Required, Array, enum values below
  "customTimes": [],              // Optional, Array of timestamps (for custom frequency)
  "startDate": Timestamp,         // Required
  "endDate": Timestamp,           // Optional (null = no end)
  "activeDays": [1,2,3,4,5],     // Required for weekly, Array of integers (1=Mon, 7=Sun)
  "reminderEnabled": true,        // Required, Boolean
  "createdBy": "userId",          // Required
  "createdAt": Timestamp,         // Required
  "updatedAt": Timestamp          // Required
}
```

#### Time Periods Enum Values:
- "morning" (6am-12pm), "afternoon" (12pm-6pm), "evening" (6pm-10pm), "bedtime" (10pm-12am)

### 7. Dose Document Structure
```javascript
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "itemId": "medicationId",       // Required, reference to medication/supplement/diet
  "itemType": "medication",       // Required, enum: "medication", "supplement", "diet"
  "scheduledTime": Timestamp,     // Required, when to take
  "period": "morning",            // Required, from schedule timePeriods
  "isTaken": false,               // Required, Boolean
  "takenAt": Timestamp,           // Optional, when actually taken
  "notes": "Felt nauseous",       // Optional, max 200 chars
  "createdBy": "userId",          // Required
  "createdAt": Timestamp,         // Required
  "updatedAt": Timestamp          // Required
}
```

---

## Permission Model

### Role Hierarchy:

| Role | adminIds | memberIds | writePermissionIds | Can Add/Edit Items | Can View | Can Manage Members |
|------|----------|-----------|-------------------|-------------------|----------|-------------------|
| SuperAdmin (Creator) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Admin | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Member | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |

### Permission Checks (Pseudo-code):
```kotlin
// Android
fun canUserWrite(userId: String, group: Group): Boolean {
    return group.writePermissionIds.contains(userId)
}

fun canUserManageMembers(userId: String, group: Group): Boolean {
    return group.createdBy == userId // Only superadmin
}
```

---

## API Operations

### 1. Create Group
```kotlin
// Android Implementation
fun createGroup(name: String): Group {
    val groupId = UUID.randomUUID().toString()
    val inviteCode = generateInviteCode() // 6 char alphanumeric
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: throw Exception("Not authenticated")
    
    val group = hashMapOf(
        "id" to groupId,
        "name" to name.take(50), // Enforce max length
        "inviteCode" to inviteCode,
        "createdBy" to userId,
        "adminIds" to listOf(userId),
        "memberIds" to listOf(userId),
        "writePermissionIds" to listOf(userId),
        "createdAt" to FieldValue.serverTimestamp(),
        "updatedAt" to FieldValue.serverTimestamp()
    )
    
    // Save to Firestore
    FirebaseFirestore.getInstance()
        .collection("groups")
        .document(groupId)
        .set(group)
        
    return group
}

fun generateInviteCode(): String {
    val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return (1..6)
        .map { chars.random() }
        .joinToString("")
}
```

### 2. Join Group
```kotlin
fun joinGroup(inviteCode: String, memberName: String) {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: throw Exception("Not authenticated")
    
    // Find group by invite code
    FirebaseFirestore.getInstance()
        .collection("groups")
        .whereEqualTo("inviteCode", inviteCode.uppercase())
        .get()
        .addOnSuccessListener { documents ->
            if (documents.isEmpty) throw Exception("Invalid invite code")
            
            val group = documents.first()
            val memberIds = group.get("memberIds") as List<String>
            
            // Check limits
            if (memberIds.size >= 3) throw Exception("Group is full")
            if (memberIds.contains(userId)) throw Exception("Already a member")
            
            // Add to group
            group.reference.update(
                "memberIds", FieldValue.arrayUnion(userId),
                "updatedAt", FieldValue.serverTimestamp()
            )
            
            // Create member document
            val member = hashMapOf(
                "id" to UUID.randomUUID().toString(),
                "userId" to userId,
                "groupId" to group.id,
                "name" to memberName.take(50),
                "role" to "member",
                "permissions" to "read",
                "joinedAt" to FieldValue.serverTimestamp()
            )
            
            group.reference.collection("members")
                .document(userId)
                .set(member)
        }
}
```

### 3. Add Medication (With Permission Check)
```kotlin
fun addMedication(medication: Medication) {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: throw Exception("Not authenticated")
    
    // 1. Always save to personal space
    val personalRef = FirebaseFirestore.getInstance()
        .collection("users")
        .document(userId)
        .collection("medications")
        .document(medication.id)
    
    personalRef.set(medication.toMap())
    
    // 2. If in a group, check permissions and sync
    currentGroup?.let { group ->
        if (group.writePermissionIds.contains(userId)) {
            // User has write permission, sync to group
            val groupRef = FirebaseFirestore.getInstance()
                .collection("groups")
                .document(group.id)
                .collection("member_medications")
                .document("${userId}_${medication.id}")
            
            val reference = hashMapOf(
                "userId" to userId,
                "medicationId" to medication.id,
                "personalDataPath" to "users/$userId/medications/${medication.id}",
                "updatedAt" to FieldValue.serverTimestamp()
            )
            
            groupRef.set(reference)
        } else {
            // User is read-only member, cannot sync to group
            Log.w("Permissions", "User lacks write permission in group")
        }
    }
}
```

### 4. Fetch All Medications (Personal + Group)
```kotlin
fun fetchAllMedications(): List<Medication> {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return emptyList()
    val medications = mutableListOf<Medication>()
    
    // 1. Fetch personal medications
    val personalMeds = FirebaseFirestore.getInstance()
        .collection("users")
        .document(userId)
        .collection("medications")
        .get()
        .await()
        .documents
        .mapNotNull { it.toObject<Medication>() }
    
    medications.addAll(personalMeds)
    
    // 2. If in group, fetch other members' medications
    currentGroup?.let { group ->
        val groupMedRefs = FirebaseFirestore.getInstance()
            .collection("groups")
            .document(group.id)
            .collection("member_medications")
            .get()
            .await()
        
        for (doc in groupMedRefs.documents) {
            val refUserId = doc.getString("userId") ?: continue
            if (refUserId == userId) continue // Skip own medications
            
            val path = doc.getString("personalDataPath") ?: continue
            val medDoc = FirebaseFirestore.getInstance()
                .document(path)
                .get()
                .await()
            
            medDoc.toObject<Medication>()?.let { medications.add(it) }
        }
    }
    
    return medications
}
```

### 5. Promote Member to Admin
```kotlin
fun promoteMemberToAdmin(memberId: String) {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: throw Exception("Not authenticated")
    val group = currentGroup ?: throw Exception("No active group")
    
    // Only superadmin can promote
    if (group.createdBy != userId) throw Exception("Only group creator can promote members")
    
    // Update group document
    val groupRef = FirebaseFirestore.getInstance()
        .collection("groups")
        .document(group.id)
    
    groupRef.update(
        "adminIds", FieldValue.arrayUnion(memberId),
        "writePermissionIds", FieldValue.arrayUnion(memberId),
        "updatedAt", FieldValue.serverTimestamp()
    )
    
    // Update member document
    groupRef.collection("members")
        .document(memberId)
        .update(
            "role", "admin",
            "permissions", "write"
        )
}
```

---

## Error Handling

### Standard Error Codes
```kotlin
enum class HealthError(val code: String, val message: String) {
    NOT_AUTHENTICATED("AUTH_001", "User not authenticated"),
    GROUP_NOT_FOUND("GROUP_001", "Group not found"),
    GROUP_FULL("GROUP_002", "Group already has 3 members"),
    ALREADY_MEMBER("GROUP_003", "Already a member of this group"),
    NO_PERMISSION("PERM_001", "No write permission in group"),
    NOT_ADMIN("PERM_002", "Only admins can perform this action"),
    NOT_SUPERADMIN("PERM_003", "Only group creator can perform this action"),
    INVALID_INVITE_CODE("INVITE_001", "Invalid or expired invite code"),
    MEDICATION_LIMIT("LIMIT_001", "Maximum 6 medications allowed"),
    SUPPLEMENT_LIMIT("LIMIT_002", "Maximum 4 supplements allowed"),
    DIET_LIMIT("LIMIT_003", "Maximum 12 diet items allowed"),
    NETWORK_ERROR("NET_001", "Network connection failed"),
    SYNC_FAILED("SYNC_001", "Failed to sync with cloud")
}
```

### Error Response Format
```json
{
  "success": false,
  "error": {
    "code": "GROUP_002",
    "message": "Group already has 3 members",
    "details": "Contact group admin to remove inactive member"
  }
}
```

---

## Real-time Sync

### Setting up Listeners
```kotlin
// Listen to personal medications
private fun listenToPersonalMedications() {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
    
    FirebaseFirestore.getInstance()
        .collection("users")
        .document(userId)
        .collection("medications")
        .addSnapshotListener { snapshot, error ->
            if (error != null) {
                handleError(error)
                return@addSnapshotListener
            }
            
            val medications = snapshot?.documents
                ?.mapNotNull { it.toObject<Medication>() }
                ?: emptyList()
            
            updateUI(medications)
        }
}

// Listen to group changes
private fun listenToGroupChanges(groupId: String) {
    FirebaseFirestore.getInstance()
        .collection("groups")
        .document(groupId)
        .addSnapshotListener { snapshot, error ->
            if (error != null) return@addSnapshotListener
            
            snapshot?.let { doc ->
                val memberIds = doc.get("memberIds") as? List<String> ?: emptyList()
                val adminIds = doc.get("adminIds") as? List<String> ?: emptyList()
                
                // Update local permission state
                updatePermissions(memberIds, adminIds)
            }
        }
}
```

### Conflict Resolution
- **Strategy**: Last Write Wins
- **Implementation**: Always use `updatedAt` timestamp
- **Merge Logic**: Item with latest `updatedAt` takes precedence

---

## Edge Cases

### 1. User Reinstalls App
```kotlin
// Check if user had previous data
fun checkPreviousData() {
    val userId = FirebaseAuth.getInstance().currentUser?.uid ?: return
    
    // This will be a NEW userId after reinstall
    // Previous data is orphaned but still exists in Firebase
    // Solution: Use persistent login or backup/restore mechanism
}
```

### 2. Network Offline
```kotlin
// Enable offline persistence
FirebaseFirestore.getInstance().apply {
    firestoreSettings = FirebaseFirestoreSettings.Builder()
        .setPersistenceEnabled(true)
        .setCacheSizeBytes(FirebaseFirestoreSettings.CACHE_SIZE_UNLIMITED)
        .build()
}
```

### 3. Member Removed While Offline
- Check membership on app launch
- If removed, clear group data locally
- Maintain personal data

### 4. Concurrent Edits
- Use Firebase Transactions for critical updates
- Example: Updating member count
```kotlin
firestore.runTransaction { transaction ->
    val groupDoc = transaction.get(groupRef)
    val currentMembers = groupDoc.get("memberIds") as List<String>
    
    if (currentMembers.size >= 3) {
        throw Exception("Group full")
    }
    
    transaction.update(groupRef, "memberIds", 
        FieldValue.arrayUnion(newMemberId))
}
```

### 5. Invite Code Collision
- Probability: 1 in 2,176,782,336 (36^6)
- Handle: Regenerate if collision detected
```kotlin
fun generateUniqueInviteCode(): String {
    var inviteCode: String
    var attempts = 0
    
    do {
        inviteCode = generateInviteCode()
        val exists = checkInviteCodeExists(inviteCode)
        attempts++
        
        if (attempts > 10) throw Exception("Failed to generate unique code")
    } while (exists)
    
    return inviteCode
}
```

---

## Testing Checklist

### Unit Tests
- [ ] UUID generation and formatting
- [ ] Invite code generation (6 chars, uppercase)
- [ ] Permission checks (read/write/admin)
- [ ] Data validation (max lengths, required fields)
- [ ] Enum value validation

### Integration Tests
- [ ] iOS creates group → Android joins with invite code
- [ ] Android creates group → iOS joins with invite code
- [ ] iOS admin adds medication → visible on Android member's device
- [ ] Android admin adds supplement → visible on iOS member's device
- [ ] Real-time sync works bi-directionally
- [ ] Member promotion/demotion reflects on both platforms
- [ ] Offline mode → Online sync works correctly

### Stress Tests
- [ ] 3 users adding medications simultaneously
- [ ] Rapid permission changes
- [ ] Large dataset (100+ medications)
- [ ] Poor network conditions
- [ ] App backgrounding/foregrounding

### Security Tests
- [ ] Members cannot write without permission
- [ ] Non-members cannot read group data
- [ ] SQL injection attempts in text fields
- [ ] Invalid data types rejected
- [ ] Expired invite codes don't work

---

## Firebase Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    function isMemberOf(groupId) {
      return isAuthenticated() && 
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
    }
    
    function hasWritePermission(groupId) {
      return isAuthenticated() && 
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds;
    }
    
    function isGroupAdmin(groupId) {
      return isAuthenticated() && 
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.adminIds;
    }
    
    function isSuperAdmin(groupId) {
      return isAuthenticated() && 
        request.auth.uid == get(/databases/$(database)/documents/groups/$(groupId)).data.createdBy;
    }
    
    // Users can only access their own data
    match /users/{userId}/{document=**} {
      allow read, write: if isOwner(userId);
    }
    
    // Group rules
    match /groups/{groupId} {
      // Members can read group info
      allow read: if isMemberOf(groupId);
      
      // Only admins can update group (except member lists)
      allow update: if isGroupAdmin(groupId) && 
        !request.resource.data.diff(resource.data).affectedKeys()
          .hasAny(['memberIds', 'adminIds', 'createdBy']);
      
      // Only superadmin can manage members
      allow update: if isSuperAdmin(groupId) && 
        request.resource.data.diff(resource.data).affectedKeys()
          .hasAny(['memberIds', 'adminIds', 'writePermissionIds']);
      
      // Anyone can create a group
      allow create: if isAuthenticated() && 
        request.resource.data.createdBy == request.auth.uid &&
        request.resource.data.memberIds.size() == 1 &&
        request.resource.data.adminIds.size() == 1;
    }
    
    // Group subcollections
    match /groups/{groupId}/members/{memberId} {
      allow read: if isMemberOf(groupId);
      allow write: if isSuperAdmin(groupId);
    }
    
    match /groups/{groupId}/member_medications/{docId} {
      allow read: if isMemberOf(groupId);
      allow write: if hasWritePermission(groupId);
    }
    
    match /groups/{groupId}/member_supplements/{docId} {
      allow read: if isMemberOf(groupId);
      allow write: if hasWritePermission(groupId);
    }
    
    match /groups/{groupId}/member_diets/{docId} {
      allow read: if isMemberOf(groupId);
      allow write: if hasWritePermission(groupId);
    }
  }
}
```

---

## Migration Strategy

### From Local to Cloud
```kotlin
fun migrateLocalDataToFirebase() {
    // 1. Get all local data
    val localMedications = localDatabase.getAllMedications()
    
    // 2. Batch upload to Firebase
    val batch = FirebaseFirestore.getInstance().batch()
    
    localMedications.forEach { medication ->
        val ref = FirebaseFirestore.getInstance()
            .collection("users")
            .document(userId)
            .collection("medications")
            .document(medication.id)
        
        batch.set(ref, medication.toFirebaseMap())
    }
    
    batch.commit()
        .addOnSuccessListener { 
            // 3. Clear local database after successful upload
            localDatabase.clearAll()
        }
}
```

---

## Version Compatibility

### Minimum SDK Versions
- **iOS**: Firebase iOS SDK 10.0+, iOS 14.0+
- **Android**: Firebase Android SDK 32.0+, Android API 24+

### Handling Unknown Fields
```kotlin
// Android - Use @IgnoreExtraProperties
@IgnoreExtraProperties
data class Medication(
    val id: String = "",
    val name: String = "",
    // ... other fields
)

// iOS - Codable handles this automatically
struct Medication: Codable {
    let id: String
    let name: String
    // Unknown fields are ignored
}
```

### Version Check
```kotlin
// Add app version to member document for compatibility tracking
val member = hashMapOf(
    // ... other fields
    "appVersion" to BuildConfig.VERSION_NAME,
    "platform" to "android", // or "ios"
    "lastUpdated" to FieldValue.serverTimestamp()
)
```

---

## Performance Optimization

### Pagination
```kotlin
fun loadMedications(lastDocument: DocumentSnapshot? = null) {
    var query = FirebaseFirestore.getInstance()
        .collection("users")
        .document(userId)
        .collection("medications")
        .orderBy("createdAt", Query.Direction.DESCENDING)
        .limit(20)
    
    lastDocument?.let {
        query = query.startAfter(it)
    }
    
    query.get().addOnSuccessListener { /* handle results */ }
}
```

### Caching Strategy
- Use Firebase offline persistence
- Cache frequently accessed data in memory
- Implement TTL (Time To Live) for cached data
- Clear cache on logout

---

## Monitoring & Analytics

### Track Key Events
```kotlin
// Using Firebase Analytics
Firebase.analytics.logEvent("group_created") {
    param("group_size", 1)
}

Firebase.analytics.logEvent("medication_added") {
    param("has_group", currentGroup != null)
    param("user_role", currentUserRole)
}

Firebase.analytics.logEvent("invite_code_used") {
    param("group_size_after", memberCount)
}
```

### Error Tracking
```kotlin
// Using Firebase Crashlytics
FirebaseCrashlytics.getInstance().apply {
    setUserId(hashedUserId) // Hash for privacy
    setCustomKey("group_id", currentGroup?.id ?: "none")
    setCustomKey("user_role", currentUserRole)
    
    recordException(exception)
}
```

---

## Support & Debugging

### Debug Logging
```kotlin
// Debug mode only
if (BuildConfig.DEBUG) {
    FirebaseFirestore.setLoggingEnabled(true)
}

// Custom logging
object FirebaseLogger {
    fun logOperation(operation: String, data: Map<String, Any>) {
        if (BuildConfig.DEBUG) {
            Log.d("Firebase", "$operation: $data")
        }
        
        // Also send to analytics in production
        Firebase.analytics.logEvent("firebase_operation") {
            param("operation", operation)
        }
    }
}
```

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Data not syncing | No internet | Enable offline persistence |
| Permission denied | Not in group | Check membership before operations |
| Group full error | 3 members max | Show user-friendly message |
| Duplicate medications | Sync conflict | Use transaction for updates |
| Missing data after reinstall | New anonymous user | Implement account linking |

---

## Contact & Resources

- **Firebase Documentation**: https://firebase.google.com/docs
- **iOS Repository**: [Your GitHub repo]
- **Android Repository**: [Android team's repo]
- **Shared Test Project**: [Firebase project ID]
- **Test Invite Codes**: 
  - iOS Test Group: "IOSTST"
  - Android Test Group: "ANDTST"
  - Cross-Platform Test: "XPLATF"

### Team Contacts
- **iOS Lead**: [Your email]
- **Android Lead**: [Their email]
- **Firebase Admin**: [Admin email]

### Version History
- v1.0 - Initial specification (December 2024)
- v1.1 - Added error codes and edge cases
- v1.2 - Added security rules and migration strategy

---

## Appendix A: Quick Reference

### Firebase Methods Cheat Sheet

| Operation | iOS (Swift) | Android (Kotlin) |
|-----------|------------|------------------|
| Get current user | `Auth.auth().currentUser?.uid` | `FirebaseAuth.getInstance().currentUser?.uid` |
| Server timestamp | `FieldValue.serverTimestamp()` | `FieldValue.serverTimestamp()` |
| Array union | `FieldValue.arrayUnion([value])` | `FieldValue.arrayUnion(value)` |
| Array remove | `FieldValue.arrayRemove([value])` | `FieldValue.arrayRemove(value)` |
| Batch write | `db.batch()` | `firestore.batch()` |
| Transaction | `db.runTransaction { }` | `firestore.runTransaction { }` |
| Realtime listener | `.addSnapshotListener { }` | `.addSnapshotListener { }` |

### Data Type Mappings

| Data Type | iOS (Swift) | Android (Kotlin) | Firestore |
|-----------|------------|------------------|-----------|
| String ID | `String` | `String` | `string` |
| Integer | `Int` | `Int` | `number` |
| Boolean | `Bool` | `Boolean` | `boolean` |
| Date/Time | `Date` | `Date` | `timestamp` |
| Array | `[String]` | `List<String>` | `array` |
| Map | `[String: Any]` | `Map<String, Any>` | `map` |
| Null | `nil` | `null` | `null` |

---

**END OF SPECIFICATION**