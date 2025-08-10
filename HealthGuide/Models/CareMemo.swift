//
//  CareMemo.swift
//  HealthGuide
//
//  Data model for audio care memos
//  Swift 6 ready with Sendable conformance
//

import Foundation
import SwiftUI

@available(iOS 18.0, *)
struct CareMemo: Identifiable, Sendable, Equatable {
    let id: UUID
    let audioFileURL: String
    let duration: TimeInterval
    let recordedAt: Date
    let transcription: String?
    let relatedMedicationIds: [UUID]
    let priority: MemoPriority
    
    init(
        id: UUID = UUID(),
        audioFileURL: String,
        duration: TimeInterval,
        recordedAt: Date = Date(),
        transcription: String? = nil,
        relatedMedicationIds: [UUID] = [],
        priority: MemoPriority = .medium
    ) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.duration = duration
        self.recordedAt = recordedAt
        self.transcription = transcription
        self.relatedMedicationIds = relatedMedicationIds
        self.priority = priority
    }
    
    // Computed properties
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: recordedAt)
    }
    
    var fileURL: URL? {
        URL(string: audioFileURL)
    }
}

@available(iOS 18.0, *)
enum MemoPriority: String, CaseIterable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var color: Color {
        switch self {
        case .high:
            return AppTheme.Colors.errorRed
        case .medium:
            return AppTheme.Colors.warningOrange
        case .low:
            return AppTheme.Colors.successGreen
        }
    }
    
    var iconName: String {
        switch self {
        case .high:
            return "exclamationmark.circle.fill"
        case .medium:
            return "info.circle.fill"
        case .low:
            return "checkmark.circle.fill"
        }
    }
}