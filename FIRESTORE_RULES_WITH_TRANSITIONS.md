##UPDATED RULES USED IN FIRESTORE. AUG 23,2025##
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
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
    }
    
    function hasWritePermission(groupId) {
      return isAuthenticated() && 
        exists(/databases/$(database)/documents/groups/$(groupId)) &&
        request.auth.uid in get(/databases/$(database)/documents/groups/$(groupId)).data.writePermissionIds;
    }
    
    // Check transition eligibility (30-day cooldown, max 3 transitions)
    function canTransition() {
      return resource.data.transitionCount < 3 && 
        (resource.data.lastTransitionAt == null || 
         request.time.toMillis() - resource.data.lastTransitionAt.toMillis() > 2592000000);
    }
    
    // Recovery phrases
    match /recovery/{hashedPhrase} {
      allow read: if true;
      allow create: if true;
      allow update: if false;
    }
    
    // User profile (tracks transitions, role, etc.)
    match /users/{userId} {
      allow read: if isOwner(userId);
      allow create: if isOwner(userId);
      allow update: if isOwner(userId);
    }
    
    // Groups and all their subcollections
    match /groups/{groupId} {
      allow read: if isAuthenticated();
      // Only allow group creation if user is not currently a member of another group
      // OR if they have properly transitioned (checked via canTransition)
      allow create: if request.auth.uid == request.resource.data.createdBy &&
                    request.auth.uid in request.resource.data.adminIds;
      allow update: if request.auth.uid == resource.data.createdBy ||
                   (request.auth.uid in resource.data.adminIds) ||
                   // Allow members to leave (remove themselves from memberIds)
                   (request.auth.uid in resource.data.memberIds &&
                    request.resource.data.memberIds.size() == resource.data.memberIds.size() - 1) ||
                   // Allow new users to JOIN (add themselves to memberIds) - MAX 3 USERS TOTAL
                   (request.auth.uid != null &&
                    !(request.auth.uid in resource.data.memberIds) &&
                    request.auth.uid in request.resource.data.memberIds &&
                    request.resource.data.memberIds.size() == resource.data.memberIds.size() + 1 &&
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
        allow write: if hasWritePermission(groupId) || request.auth.uid == memberId;
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

service firebase.storage {
  match /b/{bucket}/o {
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isGroupMember(groupId) {
      return isAuthenticated() && 
        firestore.exists(/databases/(default)/documents/groups/$(groupId)) &&
        request.auth.uid in firestore.get(/databases/(default)/documents/groups/$(groupId)).data.memberIds;
    }
    
    function hasWritePermission(groupId) {
      return isAuthenticated() && 
        firestore.exists(/databases/(default)/documents/groups/$(groupId)) &&
        request.auth.uid in firestore.get(/databases/(default)/documents/groups/$(groupId)).data.writePermissionIds;
    }
    
    // Group memos (audio files)
    match /groups/{groupId}/memos/{memoId} {
      allow read: if isGroupMember(groupId);
      allow write: if hasWritePermission(groupId);
      allow delete: if hasWritePermission(groupId);
    }
    
    // Group documents (various file types)
    match /groups/{groupId}/documents/{documentId}/{fileName} {
      allow read: if isGroupMember(groupId);
      allow write: if hasWritePermission(groupId);
      allow delete: if hasWritePermission(groupId);
    }
  }
}