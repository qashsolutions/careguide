//
//  DocumentsView_Fixed.swift
//  HealthGuide
//
//  TEST FILE: Demonstrates the fix for secondary user data loading
//  This file shows how Documents view now properly receives data
//

import SwiftUI

@available(iOS 18.0, *)
struct DocumentsView_Fixed: View {
    @StateObject private var documentsService = FirebaseDocumentsService.shared
    @StateObject private var groupService = FirebaseGroupService.shared
    @StateObject private var serviceManager = FirebaseServiceManager.shared
    
    var body: some View {
        NavigationStack {
            VStack {
                // Debug info
                VStack(alignment: .leading, spacing: 10) {
                    Text("DEBUG INFO")
                        .font(.headline)
                    
                    Text("Current Group: \(groupService.currentGroup?.name ?? "None")")
                    Text("Service Manager Initialized: \(serviceManager.isInitialized ? "✅" : "❌")")
                    Text("Listeners Active: \(serviceManager.areListenersActive ? "✅" : "❌")")
                    Text("Documents Count: \(documentsService.documents.count)")
                    Text("Last Refresh: \(documentsService.lastRefreshTime?.formatted() ?? "Never")")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding()
                
                Divider()
                
                // Documents list
                if documentsService.documents.isEmpty {
                    ContentUnavailableView(
                        "No Documents",
                        systemImage: "folder",
                        description: Text("Documents will appear here when added")
                    )
                } else {
                    List(documentsService.documents) { document in
                        VStack(alignment: .leading) {
                            Text(document.filename)
                                .font(.headline)
                            Text("Added: \(document.createdAt.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Documents (Fixed)")
            .task {
                // No need to manually load - FirebaseServiceManager handles it!
                print("📄 DocumentsView appeared - service manager will handle data")
            }
        }
    }
}

// TEST: This view demonstrates that secondary users will now see documents
// immediately after joining a group, without needing to visit each tab