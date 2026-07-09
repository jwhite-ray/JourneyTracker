//
//  HealthKitManager.swift
//  JourneyTracker
//
//  The single "distance provider". Nothing else in the app touches HealthKit.
//  Responsibilities:
//    - request READ authorization for distanceWalkingRunning + stepCount
//    - a one-time cumulative statistics query on launch / foreground
//    - an HKObserverQuery + background delivery that applies deltas even when
//      the app is not in the foreground
//    - honest, live authorization-request lifecycle state for the debug screen
//
//  Progress is driven by distanceWalkingRunning only. stepCount is read purely
//  for display. Distances are meters; timestamps are UTC (Date is absolute).
//
//  Watch-side HealthKit is deferred (KAN-6): only the iOS path is wired here.
//

import Foundation
import HealthKit
import SwiftData

/// Honest lifecycle of the one-time authorization request. HealthKit never
/// exposes whether READ access was granted, so we track the request itself,
/// not a grant/deny outcome.
enum AuthorizationPhase: String {
    case notRequested = "Not requested"
    case promptShown = "Prompt shown"
    case completed = "Request completed"
}

@Observable
@MainActor
final class HealthKitManager {

    static let shared = HealthKitManager(container: SharedModelContainer.shared)

    // MARK: Debug-visible state (observed by DebugView)

    var authorizationPhase: AuthorizationPhase = .notRequested
    /// Human-readable getRequestStatusForAuthorization result.
    var requestStatusDescription: String = "unknown"
    /// Outcome of the most recent distance query.
    var lastQueryOutcome: String = "No query yet"
    /// Latest cumulative distanceWalkingRunning since the anchor, in meters.
    var latestCumulativeDistance: Double = 0
    /// Latest cumulative step count since the anchor (secondary display stat).
    var latestStepCount: Double = 0
    /// True when the request is complete but queries PERSISTENTLY return zero
    /// (several consecutive zero readings, and enough time has elapsed since the
    /// anchor that a fresh install with no history is excluded), which usually
    /// means Health read access is off.
    var showNoDataAdvisory: Bool = false
    /// True if HealthKit is unavailable on this device at all.
    var healthDataUnavailable: Bool = false

    // MARK: Advisory heuristics (finding #5)

    /// Consecutive numeric readings that returned zero distance AND zero steps.
    private var consecutiveZeroReadings = 0
    /// Minimum consecutive zero readings before the advisory may appear.
    private static let advisoryMinimumZeroReadings = 2
    /// Minimum age of the anchor before the advisory may appear. A just-granted
    /// fresh install legitimately reads zero, so it must not be scolded.
    private static let advisoryMinimumAnchorAge: TimeInterval = 60

    // MARK: Private, non-isolated collaborators

    private nonisolated let container: ModelContainer
    private nonisolated let store = HKHealthStore()

    /// The single serialized write path for ALL delta application — foreground
    /// and background both go through this actor so they can never interleave.
    private nonisolated let progressStore: ProgressStore

    /// Retained so the observer query is not deallocated.
    private var observerQuery: HKObserverQuery?

    private nonisolated var distanceType: HKQuantityType {
        HKQuantityType(.distanceWalkingRunning)
    }
    private nonisolated var stepType: HKQuantityType {
        HKQuantityType(.stepCount)
    }
    private nonisolated var readTypes: Set<HKObjectType> {
        [distanceType, stepType]
    }

    init(container: ModelContainer) {
        self.container = container
        self.progressStore = ProgressStore(modelContainer: container)
    }

    // MARK: Lifecycle

    /// Called once on launch. Requests authorization if needed, runs the
    /// initial query, and installs the background observer.
    func start() async {
        // Seed first so the debug screen has journeys + anchor even if
        // HealthKit turns out to be unavailable on this device.
        SeedData.seedIfNeeded(in: container.mainContext)

        guard HKHealthStore.isHealthDataAvailable() else {
            healthDataUnavailable = true
            lastQueryOutcome = "HealthKit is unavailable on this device."
            return
        }

        await requestAuthorization()
        await refresh()
        startObserving()
    }

    /// AC1: request READ access. The system sheet appears once per install and
    /// lists both types. State updates live as the request progresses.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        authorizationPhase = .promptShown
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorizationPhase = .completed
        } catch {
            // The prompt may not have appeared; report honestly.
            authorizationPhase = .completed
            lastQueryOutcome = "Authorization request error: \(error.localizedDescription)"
        }
        await updateRequestStatus()
    }

    /// AC2: reflect getRequestStatusForAuthorization. This is a request-status,
    /// NOT a read-grant — we never claim "Authorized"/"Denied" for read types.
    func updateRequestStatus() async {
        let description = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(returning: "error: \(error.localizedDescription)")
                    return
                }
                switch status {
                case .unknown:
                    continuation.resume(returning: "unknown")
                case .shouldRequest:
                    continuation.resume(returning: "shouldRequest (not yet asked)")
                case .unnecessary:
                    continuation.resume(returning: "unnecessary (already requested)")
                @unknown default:
                    continuation.resume(returning: "unrecognized")
                }
            }
        }
        requestStatusDescription = description
    }

    // MARK: Foreground refresh

    /// One-time cumulative query for the foreground / launch path. The write
    /// itself is funneled through `progressStore` so it can never race the
    /// background observer's write.
    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        guard let anchorStartDate = await progressStore.anchorStartDate() else {
            lastQueryOutcome = "No progress anchor found."
            return
        }

        let now = Date()
        let distance = await cumulativeSum(distanceType, unit: .meter(), from: anchorStartDate, to: now)
        let steps = await cumulativeSum(stepType, unit: .count(), from: anchorStartDate, to: now)

        // Error reading (nil): touch nothing — no apply, no counter change.
        guard let distance else {
            lastQueryOutcome = "Distance query failed."
            return
        }

        let source = await detectSourceDevice()
        do {
            try await progressStore.apply(newCumulative: distance, sourceDevice: source, at: now)
            latestCumulativeDistance = distance
            lastQueryOutcome = "OK — cumulative \(distance) m at \(now)"
        } catch {
            // Finding #3: surface save failures instead of reporting success.
            lastQueryOutcome = "Save failed: \(error.localizedDescription)"
        }

        if let steps { latestStepCount = steps }
        recordZeroReading(distance: distance, steps: steps ?? 0)
        updateAdvisory(anchorStartDate: anchorStartDate)
    }

    /// Track consecutive all-zero numeric readings (finding #5).
    private func recordZeroReading(distance: Double, steps: Double) {
        if distance == 0 && steps == 0 {
            consecutiveZeroReadings += 1
        } else {
            consecutiveZeroReadings = 0
        }
    }

    private func updateAdvisory(anchorStartDate: Date) {
        let anchorAge = Date().timeIntervalSince(anchorStartDate)
        showNoDataAdvisory = authorizationPhase == .completed
            && consecutiveZeroReadings >= Self.advisoryMinimumZeroReadings
            && anchorAge >= Self.advisoryMinimumAnchorAge
    }

    // MARK: Background observer

    /// AC6: observe distance and enable background delivery so new distance is
    /// already applied when the app is reopened.
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable(), observerQuery == nil else { return }

        let query = HKObserverQuery(sampleType: distanceType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self else {
                completionHandler()
                return
            }
            if let error {
                // Finding #4: don't drop observer errors silently and leave a
                // stale "OK" on screen forever.
                Task { @MainActor in
                    self.lastQueryOutcome = "Observer error: \(error.localizedDescription)"
                }
                completionHandler()
                return
            }
            // Apply + save through the serialized store, THEN tell HealthKit
            // we're done — order matters so the OS keeps us alive until saved.
            Task {
                await self.handleBackgroundUpdate()
                completionHandler()
            }
        }
        store.execute(query)
        observerQuery = query

        store.enableBackgroundDelivery(for: distanceType, frequency: .immediate) { success, error in
            if let error {
                print("[HealthKitManager] enableBackgroundDelivery failed: \(error.localizedDescription)")
            } else {
                print("[HealthKitManager] background delivery enabled: \(success)")
            }
        }
    }

    /// Runs off the main actor (called from the observer's background queue).
    /// Applies the delta through the shared serialized `progressStore`, then
    /// hops to the main actor to refresh debug state.
    private nonisolated func handleBackgroundUpdate() async {
        guard let anchorStartDate = await progressStore.anchorStartDate() else { return }
        let now = Date()

        guard let distance = await cumulativeSum(distanceType, unit: .meter(), from: anchorStartDate, to: now) else {
            // Error reading (nil): touch nothing, but surface it (finding #4).
            await MainActor.run { self.lastQueryOutcome = "Background query failed." }
            return
        }
        let steps = await cumulativeSum(stepType, unit: .count(), from: anchorStartDate, to: now)
        let source = await detectSourceDevice()

        do {
            try await progressStore.apply(newCumulative: distance, sourceDevice: source, at: now)
            await MainActor.run {
                self.latestCumulativeDistance = distance
                if let steps { self.latestStepCount = steps }
                self.lastQueryOutcome = "Background update — cumulative \(distance) m at \(now)"
                self.recordZeroReading(distance: distance, steps: steps ?? 0)
                self.updateAdvisory(anchorStartDate: anchorStartDate)
            }
        } catch {
            // Finding #3: surface background save failures.
            await MainActor.run {
                self.lastQueryOutcome = "Background save failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: HealthKit query helpers (nonisolated — safe off the main actor)

    /// Cumulative sum over [from, to] using HKStatisticsQuery(.cumulativeSum).
    /// This de-duplicates overlapping iPhone + Watch samples. We NEVER sum raw
    /// HKQuantitySamples.
    ///
    /// Returns 0.0 for an EMPTY / no-data store, and nil only for a genuinely
    /// unexpected error. Finding A: on a truly empty store HealthKit surfaces
    /// no-data as an HKError (errorNoData) with a nil statistics result rather
    /// than a nil-error empty result, so that case must be mapped to a
    /// legitimate zero — otherwise fresh installs falsely report "query failed"
    /// and, worse, never feed recordZeroReading so the advisory can't fire.
    private nonisolated func cumulativeSum(
        _ type: HKQuantityType,
        unit: HKUnit,
        from: Date,
        to: Date
    ) async -> Double? {
        await withCheckedContinuation { continuation in
            // `options: []` (not .strictStartDate) is deliberate — Jake's
            // ruling in JourneyTracker_App_Concept.md: the window start is fixed
            // across queries so there's no delta drift, and counting a
            // boundary-straddling sample whole beats .strictStartDate silently
            // dropping its real post-anchor portion.
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let sum = statistics?.sumQuantity() {
                    continuation.resume(returning: sum.doubleValue(for: unit))
                } else if Self.isNoDataError(error) {
                    // Empty store / no data for this type == a legitimate zero.
                    continuation.resume(returning: 0)
                } else {
                    // Genuinely unexpected error (store inaccessible, etc.):
                    // report failure and leave the anchor untouched.
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    /// True when there was simply no data to sum: either no error at all (no
    /// samples in range) or HealthKit's explicit "no data" error.
    private nonisolated static func isNoDataError(_ error: Error?) -> Bool {
        guard let error else { return true }
        return (error as? HKError)?.code == .errorNoData
    }

    /// Best-effort device attribution of the most recent distance sample. Reads
    /// only the sample's source metadata — its value never feeds progress.
    private nonisolated func detectSourceDevice() async -> SourceDevice {
        await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: nil,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                guard let product = samples?.first?.sourceRevision.productType else {
                    continuation.resume(returning: .unknown)
                    return
                }
                if product.hasPrefix("Watch") {
                    continuation.resume(returning: .watch)
                } else if product.hasPrefix("iPhone") {
                    continuation.resume(returning: .phone)
                } else {
                    continuation.resume(returning: .unknown)
                }
            }
            store.execute(query)
        }
    }
}
