//
//  Image+SafeSystemName.swift
//  HealthGuide
//
//  Safe wrapper for SF Symbol images to prevent empty string errors
//

import SwiftUI

@available(iOS 18.0, *)
extension Image {
    /// Creates an Image from a system symbol name, with fallback for empty strings
    /// This prevents "No symbol named '' found" errors
    init(safeSystemName systemName: String?) {
        let safeName = systemName ?? ""
        if safeName.isEmpty {
            self.init(systemName: "questionmark.circle")
            #if DEBUG
            print("⚠️ Empty system name provided for Image - using fallback icon")
            #endif
        } else {
            self.init(systemName: safeName)
        }
    }
}