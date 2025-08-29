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

    // CRITICAL: Check if group's trial is still valid (14-day enforcement)
    function isTrialValid(groupId) {
      let group = get(/databases/$(database)/documents/groups/$(groupId)).data;
      // Allow access if:
      // 1. No trial end date set (shouldn't happen)
      // 2. Current time is before trial end date
      // 3. Group has active subscription
      return !exists(/databases/$(database)/documents/groups/$(groupId)) ||
             group.trialEndDate == null || 
             request.time < group.trialEndDate ||
             (group.hasActiveSubscription != null && group.hasActiveSubscription == true);
    }

    // Check if user can access group data (member + valid trial)
    function canAccessGroupData(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds &&
        isTrialValid(groupId);
    }

    // Check write permissions with trial validation
    function canWriteGroupData(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds &&
        isTrialValid(groupId);
    }

    function isGroupAdmin(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.adminIds;
    }

    // Check if user can create a group (30-day cooldown)
    function canUserCreateGroup() {
      let userDoc = /databases/$(database)/documents/users/$(request.auth.uid);
      return !exists(userDoc) || 
        (get(userDoc).data.canCreateGroup == true) ||
        (get(userDoc).data.cooldownEndDate != null && 
         request.time > get(userDoc).data.cooldownEndDate);
    }

    function isValidUserStateUpdate() {
      return !exists(/databases/$(database)/documents/users/$(request.auth.uid)) ||
      (request.resource.data.canCreateGroup == false) || 
         (request.resource.data.canCreateGroup == true && 
          resource.data.cooldownEndDate != null &&
          request.time > resource.data.cooldownEndDate);
    }

    // ============================================
    // SECURITY RULES
    // ============================================

    // Recovery phrases
    match /recovery/{hashedPhrase} {
      allow read: if true;
      allow create: if true;
      allow update: if false;
    }

    // User profile (tracks transitions and cooldowns)
    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId) && isValidUserStateUpdate();
      allow update: if isOwner(userId) && isValidUserStateUpdate();
    }

    // Join requests for admin approval
    match /joinRequests/{requestId} {
      allow read: if isAuthenticated() &&
        (request.auth.uid == resource.data.userId ||
         isGroupAdmin(resource.data.groupId));
      allow create: if isAuthenticated() &&
        request.auth.uid == request.resource.data.userId &&
        request.resource.data.status == 'pending';
      allow update: if isAuthenticated() &&
        (isGroupAdmin(resource.data.groupId) ||
         (request.auth.uid == resource.data.userId &&
          request.resource.data.status == 'cancelled'));
      allow delete: if isAuthenticated() &&
        (isGroupAdmin(resource.data.groupId) ||
         request.auth.uid == resource.data.userId);
    }

    // Groups
    match /groups/{groupId} {
      // Always allow read of group metadata (to check trial status)
      allow read: if isAuthenticated();
      
      // Group creation enforces cooldown
      allow create: if request.auth.uid == request.resource.data.createdBy &&
                    request.auth.uid in request.resource.data.adminIds &&
                    canUserCreateGroup();
      
      // Updates require valid trial
      allow update: if isTrialValid(groupId) && (
                   request.auth.uid == resource.data.createdBy ||
                   (request.auth.uid in resource.data.adminIds) ||
                   (request.auth.uid in resource.data.memberIds &&
                    request.resource.data.memberIds.size() == resource.data.memberIds.size() - 1) ||
                   (request.auth.uid in resource.data.adminIds &&
                    request.resource.data.memberIds.size() <= 3));
      
      allow delete: if request.auth.uid == resource.data.createdBy && isTrialValid(groupId);

      // ============================================
      // SUBCOLLECTIONS - ALL ENFORCE TRIAL EXPIRY
      // ============================================
      
      // Group medications - TRIAL ENFORCED
      match /medications/{medicationId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group supplements - TRIAL ENFORCED
      match /supplements/{supplementId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group diets - TRIAL ENFORCED
      match /diets/{dietId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group doses - TRIAL ENFORCED
      match /doses/{doseId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group schedules - TRIAL ENFORCED
      match /schedules/{scheduleId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group contacts - TRIAL ENFORCED
      match /contacts/{contactId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group memos - TRIAL ENFORCED
      match /memos/{memoId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group documents - TRIAL ENFORCED
      match /documents/{documentId} {
        allow read: if canAccessGroupData(groupId);
        allow create, update, delete: if canWriteGroupData(groupId);
      }

      // Group members - TRIAL ENFORCED
      match /members/{memberId} {
        allow read: if canAccessGroupData(groupId);
        allow write: if canWriteGroupData(groupId) || 
                       (request.auth.uid == memberId && isTrialValid(groupId));
      }

      // Join requests (subcollection) - Always allowed during/after trial
      match /joinRequests/{requestId} {
        allow read: if isGroupAdmin(groupId);
        allow create: if isAuthenticated() &&
          !(request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds) &&
          request.auth.uid == request.resource.data.userId;
        allow update: if isGroupAdmin(groupId);
        allow delete: if isGroupAdmin(groupId) || request.auth.uid == resource.data.userId;
      }
    }

    // Invite codes - No trial restriction (needed for joining)
    match /inviteCodes/{inviteCode} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if false;
      allow delete: if isAuthenticated();
    }
  }
}

// ============================================
// CRITICAL TRIAL ENFORCEMENT SUMMARY:
// ============================================
// 1. After day 14 (trialEndDate passes):
//    - NO read access to medications, supplements, contacts, memos, documents
//    - NO write access to any data
//    - NO updates to group settings
//    
// 2. Users must have active subscription to access data after trial
//
// 3. This prevents bypassing client-side checks
//
// 4. Group metadata can still be read (to show trial expired message)
//
// 5. Join requests can still be created (to rejoin after cooldown)