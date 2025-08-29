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

    function isGroupMember(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in
get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
    }

    function hasWritePermission(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$
(groupId)).data.writePermissionIds;
    }


    // Helper function to check if user is group admin
    function isGroupAdmin(groupId) {
      return isAuthenticated() &&
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in
get(/databases/$(database)/documents/groups/$(groupId)).data.adminIds;
    }

    // **NEW: Check if user can create a group (cooldown enforcement)**
    function canUserCreateGroup() {
      let userDoc = /databases/$(database)/documents/users/$(request.auth.uid);
      return !exists(userDoc) || 
        (get(userDoc).data.canCreateGroup == true) ||
        (get(userDoc).data.cooldownEndDate != null && 
         request.time > get(userDoc).data.cooldownEndDate);
    }

    // **NEW: Validate user state transitions**
    function isValidUserStateUpdate() {
      // Allow setting initial state for new users
      return !exists(/databases/$(database)/documents/users/$(request.auth.uid)) ||
      
      // Prevent manipulation of critical cooldown fields by non-admin operations
      // Only allow canCreateGroup to be set to false (when joining group) 
      // or true (when cooldown expires via Cloud Function)
      (request.resource.data.canCreateGroup == false) || 
         (request.resource.data.canCreateGroup == true && 
          resource.data.cooldownEndDate != null &&
          request.time > resource.data.cooldownEndDate);
    }

    // Recovery phrases
    match /recovery/{hashedPhrase} {
      allow read: if true;
      allow create: if true;
      allow update: if false;
    }

    // User profile (tracks transitions, role, cooldown state)
    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId) && isValidUserStateUpdate();
      allow update: if isOwner(userId) && isValidUserStateUpdate();
    }

    // Join requests collection for admin approval flow
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
      allow read: if isAuthenticated();
      
      // **UPDATED: Group creation now enforces cooldown**
      allow create: if request.auth.uid == request.resource.data.createdBy &&
                    request.auth.uid in request.resource.data.adminIds &&
                    canUserCreateGroup();
      
      allow update: if request.auth.uid == resource.data.createdBy ||
                   (request.auth.uid in resource.data.adminIds) ||
                   // Allow members to leave (remove themselves)
                   (request.auth.uid in resource.data.memberIds &&
                    request.resource.data.memberIds.size() ==
resource.data.memberIds.size() - 1) ||
                   // Only admins can add members (after approving join requests)
                   (request.auth.uid in resource.data.adminIds &&
                    request.resource.data.memberIds.size() <= 3);
      
      allow delete: if request.auth.uid == resource.data.createdBy;

      // Group medications
      match /medications/{medicationId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group supplements
      match /supplements/{supplementId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group diets
      match /diets/{dietId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group doses
      match /doses/{doseId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group schedules
      match /schedules/{scheduleId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group contacts
      match /contacts/{contactId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group memos
      match /memos/{memoId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group documents
      match /documents/{documentId} {
        allow read: if isGroupMember(groupId);
        allow create, update, delete: if hasWritePermission(groupId);
      }

      // Group members
      match /members/{memberId} {
        allow read: if isGroupMember(groupId);
        allow write: if hasWritePermission(groupId) || request.auth.uid
== memberId;
      }

      // Join requests specific to a group (subcollection)
      match /joinRequests/{requestId} {
        // Members and admins can read join requests for the group
        allow read: if isGroupMember(groupId) || isGroupAdmin(groupId);

        // Anyone can create a request to join (but not if already a member)
        allow create: if isAuthenticated() &&
          !(request.auth.uid in
get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds)
&&
          request.auth.uid == request.resource.data.userId;

        // Only admins can approve/deny (update status)
        allow update: if isGroupAdmin(groupId);

        // Admin or requester can delete
        allow delete: if isGroupAdmin(groupId) || request.auth.uid ==
resource.data.userId;
      }

      // Old collections from previous architecture (for cleanup)
      match /member_medications/{docId} {
        allow read: if isGroupMember(groupId);
        allow write: if hasWritePermission(groupId);
      }

      match /member_supplements/{docId} {
        allow read: if isGroupMember(groupId);
        allow write: if hasWritePermission(groupId);
      }

      match /member_diets/{docId} {
        allow read: if isGroupMember(groupId);
        allow write: if hasWritePermission(groupId);
      }
    }

    // Invite codes
    match /inviteCodes/{inviteCode} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if false;
      allow delete: if isAuthenticated();
    }

    // Shared data (keeping for backward compatibility)
    match /sharedData/{groupId}/{collection}/{document} {
      allow read: if request.auth.uid in

get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
      allow write: if request.auth.uid in
get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds;
    }
  }
}
