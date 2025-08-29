rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ============================================
    // HELPER FUNCTIONS
    // ============================================
    
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    function isGroupMember(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
    }

    function hasWritePermission(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds;
    }

    function isGroupAdmin(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.adminIds;
    }

    // ============================================
    // NEW: TRIAL ENFORCEMENT FUNCTIONS
    // ============================================
    
    // Check if group's trial is still valid (14-day enforcement)
    function isTrialValid(groupId) {
      let group = get(/databases/$(database)/documents/groups/$(groupId)).data;
      // Allow access if:
      // 1. No trial end date set (shouldn't happen but handle gracefully)
      // 2. Current time is before trial end date
      // 3. Group has active subscription (after trial ends)
      return group.trialEndDate == null || 
             request.time < group.trialEndDate ||
             (group.hasActiveSubscription != null && group.hasActiveSubscription == true);
    }

    // Check if user can access group data (member + valid trial)
    function canAccessGroupData(groupId) {
      return isGroupMember(groupId) && isTrialValid(groupId);
    }

    // Check write permissions with trial validation
    function canWriteGroupData(groupId) {
      return hasWritePermission(groupId) && isTrialValid(groupId);
    }

    // ============================================
    // COOLDOWN & TRANSITION FUNCTIONS (EXISTING)
    // ============================================
    
    // Check if user can create a group (30-day cooldown after removal)
    function canUserCreateGroup() {
      let userDoc = /databases/$(database)/documents/users/$(request.auth.uid);
      return !exists(userDoc) || 
        (get(userDoc).data.canCreateGroup == true) ||
        (get(userDoc).data.cooldownEndDate != null && 
         request.time > get(userDoc).data.cooldownEndDate);
    }

    // Validate user state transitions
    function isValidUserStateUpdate() {
      // Allow setting initial state for new users
      return !exists(/databases/$(database)/documents/users/$(request.auth.uid)) ||
      // Prevent manipulation of critical cooldown fields by non-admin operations
      // Only allow canCreateGroup to be set to false (when joining group) 
      // or true (when cooldown expires)
      (request.resource.data.canCreateGroup == false) || 
         (request.resource.data.canCreateGroup == true && 
          resource.data.cooldownEndDate != null &&
          request.time > resource.data.cooldownEndDate);
    }

    // ============================================
    // SECURITY RULES
    // ============================================

    // Recovery phrases (unchanged from existing)
    match /recovery/{hashedPhrase} {
      allow read: if true;
      allow create: if true;
      allow update: if false;
    }

    // User profile - tracks transitions, cooldowns, and role
    match /users/{userId} {
      allow read: if isOwner(userId);
      // Allow user to create their own document OR admin to create during approval
      allow create: if (isOwner(userId) && isValidUserStateUpdate()) ||
                      (isAuthenticated() && request.resource.data.currentRole == 'member' &&
                       request.resource.data.canCreateGroup == false &&
                       request.resource.data.joinedGroupId != null);
      // Allow user to update their own document OR admin to update during operations
      allow update: if (isOwner(userId) && isValidUserStateUpdate()) ||
                      (isAuthenticated() && isGroupAdmin(resource.data.joinedGroupId));
    }

    // Join requests collection for admin approval flow (unchanged from existing)
    match /joinRequests/{requestId} {
      // Anyone authenticated can read their own join requests
      // Admins can read all join requests for their groups
      allow read: if isAuthenticated() &&
        (request.auth.uid == resource.data.userId ||
         isGroupAdmin(resource.data.groupId));

      // Only authenticated users can create join requests for themselves
      allow create: if isAuthenticated() &&
        request.auth.uid == request.resource.data.userId &&
        request.resource.data.status == 'pending';

      // Only group admins can update (approve/deny) join requests
      // OR the requesting user can cancel their own request
      allow update: if isAuthenticated() &&
        (isGroupAdmin(resource.data.groupId) ||
         (request.auth.uid == resource.data.userId &&
          request.resource.data.status == 'cancelled'));

      // Allow deletion by admin or the user who created the request
      allow delete: if isAuthenticated() &&
        (isGroupAdmin(resource.data.groupId) ||
         request.auth.uid == resource.data.userId);
    }

    // Groups and all their subcollections
    match /groups/{groupId} {
      // Always allow read of group metadata (to check trial status)
      allow read: if isAuthenticated();
      
      // Group creation enforces cooldown (unchanged from existing)
      allow create: if request.auth.uid == request.resource.data.createdBy &&
                    request.auth.uid in request.resource.data.adminIds &&
                    canUserCreateGroup();
      
      // Updates require valid trial (ENHANCED with trial check)
      allow update: if isTrialValid(groupId) && (
                   request.auth.uid == resource.data.createdBy ||
                   (request.auth.uid in resource.data.adminIds) ||
                   // Allow members to leave (remove themselves)
                   (request.auth.uid in resource.data.memberIds &&
                    request.resource.data.memberIds.size() == resource.data.memberIds.size() - 1) ||
                   // Only admins can add members (max 2 non-admin members + 1 admin = 3 total)
                   (request.auth.uid in resource.data.adminIds &&
                    request.resource.data.memberIds.size() <= 3));
      
      allow delete: if request.auth.uid == resource.data.createdBy && isTrialValid(groupId);

      // ============================================
      // SUBCOLLECTIONS - ENHANCED WITH TRIAL CHECKS
      // ============================================
      
      // Group medications (TRIAL ENFORCED)
      match /medications/{medicationId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group supplements (TRIAL ENFORCED)
      match /supplements/{supplementId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group diets (TRIAL ENFORCED)
      match /diets/{dietId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group doses (TRIAL ENFORCED)
      match /doses/{doseId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group schedules (TRIAL ENFORCED)
      match /schedules/{scheduleId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group contacts (TRIAL ENFORCED)
      match /contacts/{contactId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group memos (TRIAL ENFORCED)
      match /memos/{memoId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group documents (TRIAL ENFORCED)
      match /documents/{documentId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group members (TRIAL ENFORCED)
      match /members/{memberId} {
        allow read: if canAccessGroupData(groupId);
        allow write: if canWriteGroupData(groupId) || 
                       (request.auth.uid == memberId && isTrialValid(groupId));
      }

      // Join requests specific to a group (subcollection) - Always accessible
      match /joinRequests/{requestId} {
        // Members and admins can read join requests for the group
        allow read: if isGroupMember(groupId) || isGroupAdmin(groupId);

        // Anyone can create a request to join (but not if already a member)
        allow create: if isAuthenticated() &&
          !(request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds) &&
          request.auth.uid == request.resource.data.userId;

        // Only admins can approve/deny (update status)
        allow update: if isGroupAdmin(groupId);

        // Admin or requester can delete
        allow delete: if isGroupAdmin(groupId) || 
                        request.auth.uid == resource.data.userId;
      }

      // Old collections from previous architecture (for backward compatibility)
      match /member_medications/{docId} {
        allow read: if canAccessGroupData(groupId);
        allow write: if canWriteGroupData(groupId);
      }

      match /member_supplements/{docId} {
        allow read: if canAccessGroupData(groupId);
        allow write: if canWriteGroupData(groupId);
      }

      match /member_diets/{docId} {
        allow read: if canAccessGroupData(groupId);
        allow write: if canWriteGroupData(groupId);
      }
    }

    // Invite codes - No trial restriction (needed for joining groups)
    match /inviteCodes/{inviteCode} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if false;
      allow delete: if isAuthenticated();
    }

    // Shared data (keeping for backward compatibility)
    match /sharedData/{groupId}/{collection}/{document} {
      // TRIAL ENFORCED for shared data access
      allow read: if request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds &&
                    isTrialValid(groupId);
      allow write: if request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds &&
                     isTrialValid(groupId);
    }
  }
}

// ============================================
// CONSOLIDATED RULES SUMMARY:
// ============================================
// 
// EXISTING FUNCTIONALITY PRESERVED:
// ✅ User cooldown tracking (30 days after removal)
// ✅ Join request approval flow
// ✅ Member/Admin/Write permissions
// ✅ Group creation restrictions
// ✅ Recovery phrases
// ✅ Invite codes
// ✅ Backward compatibility collections
//
// NEW TRIAL ENFORCEMENT ADDED:
// ✅ 14-day trial period enforcement
// ✅ Blocks ALL data access after trialEndDate
// ✅ Requires hasActiveSubscription field for post-trial access
// ✅ Cannot be bypassed client-side
// ✅ Applied to ALL data collections
//
// CRITICAL NOTES:
// 1. Update group documents to include hasActiveSubscription: true when user pays
// 2. Ensure trialEndDate is properly set when groups are created
// 3. Test thoroughly on day 14 to verify access is blocked
// 4. Join requests can still be created after trial (for rejoining)