//
//  HealthGuideApp.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/25/25.
//

import SwiftUI

@main
struct HealthGuideApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
