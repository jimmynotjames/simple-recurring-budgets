//
//  FirstRunSeeder.swift
//  simple-recurring-budgets
//

import Foundation
import SwiftData

/// Bootstraps the app with a single seed `Budget` on first launch per iCloud account.
///
/// Uses a **two-gate decision** to guard seeding (F-2.06, tech-design §4.5):
///
/// - **Gate A (KV flag):** The iCloud key-value store must not have `"seededV1"` set. This
///   prevents reseeding after the user intentionally deletes all their budgets.
/// - **Gate B (store count):** The SwiftData store must contain zero `Budget` records. This
///   prevents reseeding on a device where CloudKit sync replicated existing budgets faster than
///   the KV flag could arrive.
///
/// **Flag write ordering:** the KV flag is written *after* a successful `context.save()`. A
/// crash between save and flag write causes at worst one duplicate seed on next launch (the user
/// can delete it) — far better than writing the flag first and permanently suppressing seeding if
/// the save fails.
///
/// **Forward-sealing:** when Gate A is open but Gate B is closed (store already has budgets), the
/// flag is written immediately so that a later delete-all cannot accidentally trigger a reseed.
enum FirstRunSeeder {

    /// The `NSUbiquitousKeyValueStore` key that records whether first-run seeding has occurred
    /// for this iCloud account.
    ///
    /// The `V1` suffix is intentional: future changes that want to force a one-time re-seed for
    /// all users should introduce a separate key (e.g., `"seededV2"`) rather than reusing this one.
    static let firstRunSeededV1Key = "seededV1"

    /// The result of a `seedIfNeeded` call, indicating which branch was taken.
    enum SeedResult: Equatable {
        /// Both gates were open; the seed `Budget` was inserted, saved, and the KV flag was written.
        case seeded

        /// Gate A was closed (the KV flag was already set). The store count was not read and
        /// nothing was mutated.
        case skippedFlagAlreadySet

        /// Gate A was open but Gate B was closed; the store already contained at least one `Budget`.
        /// Reserved for completeness — the current implementation always forward-seals in this
        /// branch, returning `.skippedStoreNonEmptyFlagSealed` instead.
        case skippedStoreNonEmpty

        /// Gate A was open and Gate B was closed; the KV flag was forward-sealed to prevent future
        /// reseeds if the user later empties the store.
        case skippedStoreNonEmptyFlagSealed
    }

    /// Seeds a single "Food" `Budget` if this is the first launch on an empty store for this iCloud account.
    ///
    /// - Parameters:
    ///   - context: The `ModelContext` to insert into and save.
    ///   - store: A `KeyValueStore` (typically `NSUbiquitousKeyValueStore.default`) used to persist the seed flag.
    ///   - isCarryOverEnabled: Whether carry-over is enabled on the seeded `Budget`. Pass
    ///     `AppSettings.defaultCarryOverEnabled` so the seed matches what a user-created budget would get.
    ///   - now: The current date. Defaults to `Date()`. Injected so tests can pin time for
    ///     deterministic `createdAt` / `lastModified` assertions.
    /// - Returns: A `SeedResult` indicating which branch was taken.
    /// - Throws: Re-throws any error from `context.fetchCount` or `context.save()`.
    @discardableResult
    static func seedIfNeeded(
        context: ModelContext,
        store: KeyValueStore,
        isCarryOverEnabled: Bool,
        now: Date = Date()
    ) async throws -> SeedResult {

        // Gate A: KV flag — short-circuit before touching SwiftData.
        guard store.object(forKey: firstRunSeededV1Key) == nil else {
            return .skippedFlagAlreadySet
        }

        // Gate B: store count — prevents seeding when CloudKit beat the KV sync.
        let existingCount = try context.fetchCount(FetchDescriptor<Budget>())
        guard existingCount == 0 else {
            // Forward-seal: write the flag so a future delete-all doesn't trigger a reseed.
            store.set(true, forKey: firstRunSeededV1Key)
            _ = store.synchronize()
            return .skippedStoreNonEmptyFlagSealed
        }

        // Both gates open: build and insert the seed budget.
        let budget = Budget(
            name: "Food",
            allocation: 25,
            period: .daily,
            resetCadence: .weekly,         // explicit per F-2.06; matches daily.defaultResetCadence today but is a contract, not an assumption
            isCarryOverEnabled: isCarryOverEnabled
        )
        // Pin timestamps to injected `now` so callers with deterministic time get consistent results.
        budget.createdAt = now
        budget.lastModified = now

        budget.sortOrder = try Budget.nextSortOrder(for: context)
        context.insert(budget)

        // Save first; only write the flag after a successful save (see ordering docs above).
        try context.save()

        store.set(true, forKey: firstRunSeededV1Key)
        _ = store.synchronize()

        return .seeded
    }
}
