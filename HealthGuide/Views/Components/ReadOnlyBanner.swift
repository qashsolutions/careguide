//
//  ReadOnlyBanner.swift
//  HealthGuide
//
//  Banner to show when user has read-only access to group data
//

import SwiftUI

@available(iOS 18.0, *)
struct ReadOnlyBanner: View {
    @ObservedObject private var groupService = FirebaseGroupService.shared
    
    var body: some View {
        if groupService.currentGroup != nil,
           !groupService.userHasWritePermission {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "eye")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("View Only Mode")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Spacer()
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Text("You can read but cannot edit any information.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

// MARK: - Helper modifier to disable interactions for read-only users
@available(iOS 18.0, *)
struct ReadOnlyMode: ViewModifier {
    @ObservedObject private var groupService = FirebaseGroupService.shared
    
    var isEnabled: Bool {
        // If no group, user has full access (local mode)
        guard groupService.currentGroup != nil else { return true }
        // Otherwise check write permission
        return groupService.userHasWritePermission
    }
    
    func body(content: Content) -> some View {
        content
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

@available(iOS 18.0, *)
extension View {
    func readOnlyMode() -> some View {
        self.modifier(ReadOnlyMode())
    }
}