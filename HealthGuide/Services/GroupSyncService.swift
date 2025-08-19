//
//  GroupSyncService.swift
//  HealthGuide
//
//  Simple group sync using Supabase - no CloudKit complexity
//

import Foundation
import CoreData

@available(iOS 18.0, *)
@MainActor
final class GroupSyncService: ObservableObject {
    static let shared = GroupSyncService()
    
    private let baseURL = "https://zzaioxpmmjckdywssnlr.supabase.co"
    private let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp6YWlveHBtbWpja2R5d3Nzbmx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjI2NzcxNDgsImV4cCI6MjAzODI1MzE0OH0.EzCXegKCEq2u9CD9RLkGMR8dGaGfgFxYcjQnN1ynQW0"
    
    // MARK: - Create Group (Admin)
    func createGroupInCloud(name: String, inviteCode: String, adminId: String) async throws {
        let url = URL(string: "\(baseURL)/rest/v1/care_groups")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let payload = [
            "name": name,
            "invite_code": inviteCode,
            "admin_id": adminId,
            "member_count": 1,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ] as [String : Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GroupSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create group"])
        }
        
        print("✅ Group created in cloud: \(inviteCode)")
    }
    
    // MARK: - Join Group (Member)
    func joinGroupFromCloud(inviteCode: String, memberId: String, memberName: String) async throws -> GroupData? {
        // 1. Fetch group by invite code
        let url = URL(string: "\(baseURL)/rest/v1/care_groups?invite_code=eq.\(inviteCode)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let groups = try? JSONDecoder().decode([GroupData].self, from: data),
              let group = groups.first else {
            throw NSError(domain: "GroupSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid invite code"])
        }
        
        // 2. Check member count
        if group.member_count >= 3 {
            throw NSError(domain: "GroupSync", code: 3, userInfo: [NSLocalizedDescriptionKey: "Group is full (max 3 members)"])
        }
        
        // 3. Add member to group_members table
        let memberURL = URL(string: "\(baseURL)/rest/v1/group_members")!
        var memberRequest = URLRequest(url: memberURL)
        memberRequest.httpMethod = "POST"
        memberRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        memberRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        memberRequest.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let memberPayload = [
            "group_id": group.id,
            "member_id": memberId,
            "member_name": memberName,
            "can_write": true,
            "joined_at": ISO8601DateFormatter().string(from: Date())
        ] as [String : Any]
        
        memberRequest.httpBody = try JSONSerialization.data(withJSONObject: memberPayload)
        
        let (_, memberResponse) = try await URLSession.shared.data(for: memberRequest)
        
        guard let httpResponse = memberResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GroupSync", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to join group"])
        }
        
        // 4. Update member count
        await updateMemberCount(groupId: group.id, newCount: group.member_count + 1)
        
        print("✅ Joined group from cloud: \(group.name)")
        return group
    }
    
    // MARK: - Fetch Group Members
    func fetchGroupMembers(groupId: String) async throws -> [MemberData] {
        let url = URL(string: "\(baseURL)/rest/v1/group_members?group_id=eq.\(groupId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let members = try JSONDecoder().decode([MemberData].self, from: data)
        
        return members
    }
    
    // MARK: - Sync Elder's Medication Data
    func syncMedication(groupId: String, medication: MedicationData, action: SyncAction) async throws {
        let url: URL
        var request: URLRequest
        
        switch action {
        case .create, .update:
            url = URL(string: "\(baseURL)/rest/v1/elder_medications")!
            request = URLRequest(url: url)
            request.httpMethod = action == .create ? "POST" : "PATCH"
            
            let payload = [
                "group_id": groupId,
                "medication_id": medication.id,
                "medication_name": medication.name,
                "dosage": medication.dosage,
                "frequency": medication.frequency,
                "notes": medication.notes ?? "",
                "updated_at": ISO8601DateFormatter().string(from: Date()),
                "updated_by": UserManager.shared.getOrCreateUserID().uuidString
            ] as [String : Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
        case .delete:
            url = URL(string: "\(baseURL)/rest/v1/elder_medications?medication_id=eq.\(medication.id)")!
            request = URLRequest(url: url)
            request.httpMethod = "DELETE"
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GroupSync", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to sync medication"])
        }
        
        print("✅ Elder's medication synced: \(medication.name) - \(action)")
    }
    
    // MARK: - Fetch All Elder's Medications
    func fetchElderMedications(groupId: String) async throws -> [MedicationData] {
        let url = URL(string: "\(baseURL)/rest/v1/elder_medications?group_id=eq.\(groupId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let medications = try JSONDecoder().decode([MedicationData].self, from: data)
        
        return medications
    }
    
    // MARK: - Sync Action Types
    enum SyncAction {
        case create
        case update
        case delete
    }
    
    // MARK: - Helper Methods
    private func updateMemberCount(groupId: String, newCount: Int) async {
        let url = URL(string: "\(baseURL)/rest/v1/care_groups?id=eq.\(groupId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        let payload = ["member_count": newCount]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Data Models
struct GroupData: Codable {
    let id: String
    let name: String
    let invite_code: String
    let admin_id: String
    let member_count: Int
}

struct MemberData: Codable {
    let id: String
    let group_id: String
    let member_id: String
    let member_name: String
    let can_write: Bool
}

struct MedicationData: Codable {
    let id: String
    let name: String
    let dosage: String
    let frequency: String
    let notes: String?
    let updatedBy: String?
}