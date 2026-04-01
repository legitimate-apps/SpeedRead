//
//  SpeedReadApp.swift
//  SpeedRead
//
//  Created by Legitimate LLC on 4/1/26.
//

import SwiftUI
import CoreData

@main
struct SpeedReadApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
