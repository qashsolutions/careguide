//
//  FirebaseAuthService.swift
//  HealthGuide
//
//  Manages Firebase anonymous authentication
//

import Foundation
@preconcurrency import FirebaseAuth
import FirebaseCore

@available(iOS 18.0, *)
@MainActor
final class FirebaseAuthService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseAuthService()
    
    // MARK: - Properties
    @Published var isAuthenticated = false
    @Published var currentUserId: String?
    @Published var authError: String?
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    // MARK: - Initialization
    private init() {
        setupAuthListener()
    }
    
    // MARK: - Setup
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isAuthenticated = user != nil
                self?.currentUserId = user?.uid
                
                if let uid = user?.uid {
                    AppLogger.main.info("Firebase Auth: User authenticated with ID: \(uid)")
                } else {
                    AppLogger.main.info("Firebase Auth: User not authenticated")
                }
            }
        }
    }
    
    // MARK: - Sign In Anonymously
    @MainActor
    func signInAnonymously() async throws -> String {
        // Check if already signed in
        if let currentUser = Auth.auth().currentUser {
            AppLogger.main.info("Already signed in with ID: \(currentUser.uid)")
            return currentUser.uid
        }
        
        // Sign in anonymously - wrap in Task to handle Sendable
        let userId = try await Task { @MainActor in
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        }.value
        
        currentUserId = userId
        isAuthenticated = true
        
        AppLogger.main.info("Successfully signed in anonymously with ID: \(userId)")
        return userId
    }
    
    // MARK: - Get Current User ID
    func getCurrentUserId() async throws -> String {
        if let userId = Auth.auth().currentUser?.uid {
            return userId
        }
        
        // Not signed in, sign in anonymously
        return try await signInAnonymously()
    }
    
    // MARK: - Link Anonymous Account (for future use)
    @MainActor
    func linkAnonymousAccount(email: String, password: String) async throws {
        guard let user = Auth.auth().currentUser, user.isAnonymous else {
            throw AuthError.notAnonymous
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        // Wrap in Task to handle Sendable
        let userEmail = try await Task { @MainActor in
            let result = try await user.link(with: credential)
            return result.user.email
        }.value
        
        AppLogger.main.info("Anonymous account linked to: \(userEmail ?? "unknown")")
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUserId = nil
            isAuthenticated = false
            AppLogger.main.info("Successfully signed out")
        } catch {
            AppLogger.main.error("Failed to sign out: \(error)")
            authError = error.localizedDescription
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
            authStateListener = nil
        }
    }
    
    // MARK: - Error Types
    enum AuthError: LocalizedError {
        case notAnonymous
        case noUser
        
        var errorDescription: String? {
            switch self {
            case .notAnonymous:
                return "Current user is not anonymous"
            case .noUser:
                return "No authenticated user found"
            }
        }
    }
}
