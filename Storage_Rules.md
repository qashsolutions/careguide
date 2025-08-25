##STORAGE RULES
rules_version = '2';
  service firebase.storage {
    match /b/{bucket}/o {
      // Helper functions
      function isAuthenticated() {
        return request.auth != null;
      }

      function isGroupMember(groupId) {
        return isAuthenticated() &&
          firestore.exists(/databases/(default)/documents/groups/$(groupId)) &&
          request.auth.uid in
  firestore.get(/databases/(default)/documents/groups/$(groupId)).data.memberIds;
      }

      function hasWritePermission(groupId) {
        return isAuthenticated() &&
          firestore.exists(/databases/(default)/documents/groups/$(groupId)) &&
          request.auth.uid in firestore.get(/databases/(default)/documents/groups
  /$(groupId)).data.writePermissionIds;
      }

      // Group memos (audio files)
      match /groups/{groupId}/memos/{fileName} {
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
