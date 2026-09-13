//
//  TestSupport.swift
//  RingetTests
//

import Foundation
import SwiftData
@testable import Ringet

/// A fresh in-memory SwiftData container for tests that need real
/// persistence (not just plain object construction) — never touches the
/// real store.
///
/// Returns the container itself, not just its `mainContext` — callers must
/// keep the container alive for as long as they use the context. An
/// in-memory store's backing data is tied to its container's lifetime, so a
/// context outliving its container (as happened when this helper used to
/// return only `container.mainContext`) crashes on first use.
@MainActor
func makeInMemoryModelContainer() -> ModelContainer {
    let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    do {
        return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
        preconditionFailure("Failed to create in-memory ModelContainer: \(error)")
    }
}
