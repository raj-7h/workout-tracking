import HealthKit

enum HealthSync {
    static func save(exercises: [WorkoutExercise], start: Date, end: Date, dayKey: String) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        let store = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [workoutType], read: [])

        let setCount = exercises.reduce(0) { $0 + $1.sets.count }
        let repCount = exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { $0 + (Int($1.reps) ?? 0) }
        }
        let summary = exercises.map { "\($0.name): \($0.sets.count) sets, \($0.sets.reduce(0) { $0 + (Int($1.reps) ?? 0) }) reps" }.joined(separator: "\n")
        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Setwise",
            "SetwiseExerciseCount": exercises.count,
            "SetwiseSetCount": setCount,
            "SetwiseRepCount": repCount,
            "SetwiseExerciseSummary": summary,
            "SetwiseDayKey": dayKey
        ]
        let workoutEnd = max(end, start.addingTimeInterval(1))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: "SetwiseDayKey", operatorType: .equalTo, value: dayKey)
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let existing = samples ?? []
                let buildAndSave = {
                    _ = Task {
                        do {
                            let configuration = HKWorkoutConfiguration()
                            configuration.activityType = .traditionalStrengthTraining
                            configuration.locationType = .indoor
                            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
                            try await beginCollection(builder, at: start)
                            try await addMetadata(metadata, to: builder)
                            try await endCollection(builder, at: workoutEnd)
                            guard try await finishWorkout(builder) != nil else { throw HealthSyncError.saveFailed }
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                if existing.isEmpty { buildAndSave() }
                else {
                    store.delete(existing) { success, error in
                        if let error { continuation.resume(throwing: error) }
                        else if success { buildAndSave() }
                        else { continuation.resume(throwing: HealthSyncError.saveFailed) }
                    }
                }
            }
            store.execute(query)
        }
    }

    private static func beginCollection(_ builder: HKWorkoutBuilder, at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HealthSyncError.saveFailed) }
            }
        }
    }

    private static func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HealthSyncError.saveFailed) }
            }
        }
    }

    private static func endCollection(_ builder: HKWorkoutBuilder, at end: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HealthSyncError.saveFailed) }
            }
        }
    }

    private static func finishWorkout(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout?, Error>) in
            builder.finishWorkout { workout, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: workout) }
            }
        }
    }
}

enum HealthSyncError: LocalizedError {
    case unavailable, saveFailed
    var errorDescription: String? {
        switch self { case .unavailable: "Apple Health isn’t available on this device."; case .saveFailed: "Apple Health could not save the workout." }
    }
}
