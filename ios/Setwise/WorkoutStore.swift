import Foundation
import Combine

private let apiBase = URL(string: "https://workout-tracking-ebon.vercel.app")!

struct WorkoutSet: Identifiable {
    var id: Int
    var reps: String
    var weight: String
    var done: Bool
}

struct WorkoutExercise: Identifiable {
    var id: String
    var name: String
    var muscle: String
    var note: String
    var photo: String
    var videoURL: String
    var sets: [WorkoutSet]
}

struct ProgressSample: Identifiable {
    var date: Date
    var weight: Double
    var id: Date { date }
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var database: [String: Any] = ["days": [String: Any](), "templates": [String: Any]()]
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var statusMessage = "Sign in to load your workouts."
    @Published var lastCompleted: Date?
    @Published var sessionStartedAt: Date?

    private let tokenKey = "setwise.native.session"
    private var sessionToken: String? { Keychain.read(tokenKey) }
    private var currentDayKey: String { Self.dateKey(selectedDate) }
    private var currentExercises: [WorkoutExercise] { exercises(for: currentDayKey) }

    func load() async {
        guard sessionToken != nil else { statusMessage = "Sign in with Google to sync your workouts."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await request("/api/workouts")
            guard let value = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw APIError.invalidData }
            database = Self.merge(local: Self.localCopy(), remote: value)
            _ = ensureDay(currentDayKey)
            sessionStartedAt = UserDefaults.standard.object(forKey: sessionStartKey(currentDayKey)) as? Date
            statusMessage = "Workouts loaded and ready to edit."
        } catch {
            errorMessage = "Couldn’t load workouts: \(error.localizedDescription)"
        }
    }

    func signOut() { Keychain.delete(tokenKey); database = ["days": [String: Any](), "templates": [String: Any]()]; statusMessage = "Signed out."; objectWillChange.send() }
    func saveSessionToken(_ token: String) { Keychain.save(token, for: tokenKey); Task { await load() } }

    func selectDay(offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = Calendar.current.startOfDay(for: date)
        sessionStartedAt = UserDefaults.standard.object(forKey: sessionStartKey(currentDayKey)) as? Date
        _ = ensureDay(currentDayKey)
    }

    func updateSet(exerciseID: String, setIndex: Int, field: String, value: Any) {
        guard var day = dayObject(currentDayKey), var exercises = day["exercises"] as? [[String: Any]],
              let exerciseIndex = exercises.firstIndex(where: { ($0["id"] as? String) == exerciseID }),
              var sets = exercises[exerciseIndex]["sets"] as? [[String: Any]], sets.indices.contains(setIndex) else { return }
        sets[setIndex][field] = value
        exercises[exerciseIndex]["sets"] = sets
        day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        day.removeValue(forKey: "completedAt")
        setDay(currentDayKey, day)
        updateTemplate(currentDayKey)
    }

    func addSet(exerciseID: String) {
        guard var day = dayObject(currentDayKey), var exercises = day["exercises"] as? [[String: Any]],
              let index = exercises.firstIndex(where: { ($0["id"] as? String) == exerciseID }) else { return }
        var sets = exercises[index]["sets"] as? [[String: Any]] ?? []
        sets.append(["reps": "", "weight": "", "done": false])
        exercises[index]["sets"] = sets
        day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        setDay(currentDayKey, day)
        updateTemplate(currentDayKey)
    }

    func removeSet(exerciseID: String, setIndex: Int) {
        guard var day = dayObject(currentDayKey), var exercises = day["exercises"] as? [[String: Any]],
              let index = exercises.firstIndex(where: { ($0["id"] as? String) == exerciseID }),
              var sets = exercises[index]["sets"] as? [[String: Any]], sets.count > 3, sets.indices.contains(setIndex) else { return }
        sets.remove(at: setIndex); exercises[index]["sets"] = sets; day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000; setDay(currentDayKey, day); updateTemplate(currentDayKey)
    }

    func removeExercise(id: String) {
        guard var day = dayObject(currentDayKey) else { return }
        var exercises = day["exercises"] as? [[String: Any]] ?? []
        exercises.removeAll { ($0["id"] as? String) == id }
        day["exercises"] = exercises; day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        setDay(currentDayKey, day); updateTemplate(currentDayKey)
    }

    func updateNote(exerciseID: String, note: String) {
        guard var day = dayObject(currentDayKey), var exercises = day["exercises"] as? [[String: Any]],
              let index = exercises.firstIndex(where: { ($0["id"] as? String) == exerciseID }) else { return }
        exercises[index]["note"] = note
        day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        setDay(currentDayKey, day)
        updateTemplate(currentDayKey)
    }

    func updateExercise(exerciseID: String, field: String, value: Any) {
        guard var day = dayObject(currentDayKey), var exercises = day["exercises"] as? [[String: Any]],
              let index = exercises.firstIndex(where: { ($0["id"] as? String) == exerciseID }) else { return }
        exercises[index][field] = value
        day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        setDay(currentDayKey, day)
        updateTemplate(currentDayKey)
    }

    func addExercise(name: String, muscle: String, videoURL: String, photo: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var day = dayObject(currentDayKey) else { return }
        var exercises = day["exercises"] as? [[String: Any]] ?? []
        let prior = (database["days"] as? [String: [String: Any]])?.keys.filter { $0 < currentDayKey }.sorted().reversed().compactMap { key -> [String: Any]? in
            ((database["days"] as? [String: [String: Any]])?[key]?["exercises"] as? [[String: Any]])?.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }
        }.first
        exercises.append(["id": UUID().uuidString, "name": name.trimmingCharacters(in: .whitespacesAndNewlines), "muscle": muscle, "note": "", "videoUrl": videoURL.isEmpty ? (prior?["videoUrl"] as? String ?? "") : videoURL, "photo": photo.isEmpty ? (prior?["photo"] as? String ?? "") : photo, "sets": (0..<3).map { _ in ["reps": "", "weight": "", "done": false] }])
        day["exercises"] = exercises
        day["updatedAt"] = Date().timeIntervalSince1970 * 1000
        setDay(currentDayKey, day)
        updateTemplate(currentDayKey)
    }

    func beginWorkout() {
        sessionStartedAt = Date()
        UserDefaults.standard.set(sessionStartedAt, forKey: sessionStartKey(currentDayKey))
        statusMessage = "Workout timer started."
    }

    func completeDay() async {
        guard !currentExercises.isEmpty else { errorMessage = "Add exercises on this day before completing it."; return }
        isSaving = true
        defer { isSaving = false }
        do {
            var day = dayObject(currentDayKey) ?? [:]
            let now = Date()
            let start = sessionStartedAt ?? now
            day["completedAt"] = now.timeIntervalSince1970 * 1000
            day["updatedAt"] = now.timeIntervalSince1970 * 1000
            setDay(currentDayKey, day)
            let remoteData = try await request("/api/workouts")
            guard let remote = try JSONSerialization.jsonObject(with: remoteData) as? [String: Any] else { throw APIError.invalidData }
            database = Self.merge(local: database, remote: remote)
            guard let data = try? JSONSerialization.data(withJSONObject: database) else { throw APIError.invalidData }
            _ = try await request("/api/workouts", method: "PUT", body: data)
            statusMessage = "Saved to your account."
            lastCompleted = now
            do { try await HealthSync.save(exercises: currentExercises, start: start, end: now, dayKey: currentDayKey) }
            catch { errorMessage = "Saved to Setwise, but Apple Health couldn’t save this workout: \(error.localizedDescription)" }
            sessionStartedAt = nil
            UserDefaults.standard.removeObject(forKey: sessionStartKey(currentDayKey))
        } catch {
            errorMessage = "Couldn’t sync this workout: \(error.localizedDescription)"
        }
    }

    func hasSession() -> Bool { sessionToken != nil }

    func previousSets(for exerciseID: String) -> [WorkoutSet] {
        guard let days = database["days"] as? [String: [String: Any]] else { return [] }
        let prior = days.keys.filter { $0 < currentDayKey }.sorted().last
        guard let prior, let exercises = days[prior]?["exercises"] as? [[String: Any]],
              let exercise = exercises.first(where: { ($0["name"] as? String)?.caseInsensitiveCompare(name(for: exerciseID)) == .orderedSame }) else { return [] }
        return Self.sets(from: exercise)
    }

    func exercisesForUI() -> [WorkoutExercise] { currentExercises }
    func note(for id: String) -> String { currentExercises.first(where: { $0.id == id })?.note ?? "" }
    func previousNote(for exerciseID: String) -> String? {
        guard let name = currentExercises.first(where: { $0.id == exerciseID })?.name,
              let days = database["days"] as? [String: [String: Any]],
              let key = days.keys.filter({ $0 < currentDayKey }).sorted().last,
              let rows = days[key]?["exercises"] as? [[String: Any]],
              let prior = rows.first(where: { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }),
              let note = prior["note"] as? String, !note.isEmpty else { return nil }
        return note
    }
    func dateTitle() -> String { selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    func bestScore(_ exerciseID: String) -> Double {
        guard let name = currentExercises.first(where: { $0.id == exerciseID })?.name,
              let days = database["days"] as? [String: [String: Any]] else { return 0 }
        var best = 0.0
        for (date, day) in days where date < currentDayKey {
            let rows = day["exercises"] as? [[String: Any]] ?? []
            for exercise in rows where (exercise["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame {
                let sets = exercise["sets"] as? [[String: Any]] ?? []
                for set in sets {
                    let reps = Double(Self.text(set["reps"])) ?? 0
                    let weight = Double(Self.text(set["weight"])) ?? 0
                    best = max(best, reps * weight)
                }
            }
        }
        return best
    }
    func progress(_ exerciseID: String) -> [ProgressSample] {
        guard let name = currentExercises.first(where: { $0.id == exerciseID })?.name,
              let days = database["days"] as? [String: [String: Any]] else { return [] }
        return days.keys.sorted().compactMap { key in
            guard let date = Self.parseDate(key),
                  let rows = days[key]?["exercises"] as? [[String: Any]],
                  let exercise = rows.first(where: { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }),
                  let sets = exercise["sets"] as? [[String: Any]],
                  let weight = sets.map({ Double(Self.text($0["weight"])) ?? 0 }).max(), weight > 0 else { return nil }
            return ProgressSample(date: date, weight: weight)
        }
    }

    static func dateKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    private static func parseDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    private func sessionStartKey(_ date: String) -> String { "setwise.native.session-start.\(date)" }

    private func name(for id: String) -> String { currentExercises.first(where: { $0.id == id })?.name ?? "" }
    private func exercises(for key: String) -> [WorkoutExercise] {
        guard let day = dayObject(key), let rows = day["exercises"] as? [[String: Any]] else { return [] }
        return rows.enumerated().map { index, row in
            WorkoutExercise(id: row["id"] as? String ?? "\(key)-\(index)", name: row["name"] as? String ?? "Exercise", muscle: row["muscle"] as? String ?? "", note: row["note"] as? String ?? "", photo: row["photo"] as? String ?? "", videoURL: row["videoUrl"] as? String ?? "", sets: Self.sets(from: row))
        }
    }
    private static func sets(from row: [String: Any]) -> [WorkoutSet] {
        (row["sets"] as? [[String: Any]] ?? []).enumerated().map { index, set in
            WorkoutSet(id: index, reps: text(set["reps"]), weight: text(set["weight"]), done: set["done"] as? Bool ?? false)
        }
    }
    private static func text(_ value: Any?) -> String { guard let value, !(value is NSNull) else { return "" }; return String(describing: value) }
    private static func normalized(_ source: [String: Any]) -> [String: Any] {
        var copy = source
        if copy["days"] == nil { copy["days"] = [String: Any]() }
        if copy["templates"] == nil { copy["templates"] = [String: Any]() }
        if copy["templateUpdatedAt"] == nil { copy["templateUpdatedAt"] = [String: Any]() }
        return copy
    }
    private func dayObject(_ key: String) -> [String: Any]? { (database["days"] as? [String: [String: Any]])?[key] }
    private func setDay(_ key: String, _ day: [String: Any]) {
        var days = database["days"] as? [String: Any] ?? [:]
        days[key] = day; database["days"] = days
        persistLocal()
        objectWillChange.send()
    }
    private func updateTemplate(_ key: String) {
        guard let day = dayObject(key), let exercises = day["exercises"] as? [[String: Any]] else { return }
        let weekday = Self.weekday(for: selectedDate)
        let templates = exercises.map { item -> [String: Any] in
            let sets = item["sets"] as? [[String: Any]] ?? []
            return ["name": item["name"] ?? "Exercise", "muscle": item["muscle"] ?? "", "sets": sets.count, "reps": sets.last?["reps"] ?? 8, "weight": sets.last?["weight"] ?? 0, "videoUrl": item["videoUrl"] ?? "", "photo": item["photo"] ?? ""]
        }
        var all = database["templates"] as? [String: Any] ?? [:]; all[weekday] = templates; database["templates"] = all
        var times = database["templateUpdatedAt"] as? [String: Any] ?? [:]; times[weekday] = Date().timeIntervalSince1970 * 1000; database["templateUpdatedAt"] = times
        persistLocal()
    }
    private static func weekday(for date: Date) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[Calendar.current.component(.weekday, from: date) - 1]
    }
    @discardableResult private func ensureDay(_ key: String) -> Bool {
        if dayObject(key) != nil { return false }
        let weekday = Self.weekday(for: selectedDate)
        let templates = database["templates"] as? [String: [[String: Any]]] ?? [:]
        let starter: [[String: Any]] = weekday == "Monday" ? [
            ["name": "Barbell bench press", "muscle": "Chest", "sets": 3, "reps": 8, "weight": 40],
            ["name": "Incline dumbbell press", "muscle": "Chest", "sets": 3, "reps": 10, "weight": 16],
            ["name": "Shoulder press", "muscle": "Shoulders", "sets": 3, "reps": 8, "weight": 20]
        ] : []
        let prescriptions = templates[weekday] ?? starter
        let exercises: [[String: Any]] = prescriptions.map { template in
            ["id": UUID().uuidString, "name": template["name"] ?? "Exercise", "muscle": template["muscle"] ?? "", "videoUrl": template["videoUrl"] ?? "", "photo": template["photo"] ?? "", "note": "", "sets": (0..<max(3, (template["sets"] as? Int) ?? 3)).map { _ in ["reps": "", "weight": "", "done": false] }]
        }
        setDay(key, ["updatedAt": Date().timeIntervalSince1970 * 1000, "exercises": exercises])
        return true
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token = sessionToken else { throw APIError.notSignedIn }
        var request = URLRequest(url: apiBase.appending(path: path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            Keychain.delete(tokenKey)
            statusMessage = "Sign-in expired. Sign in again to sync."
            objectWillChange.send()
            throw APIError.notSignedIn
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(message ?? "Server returned \(http.statusCode).")
        }
        return data
    }

    private func persistLocal() {
        guard let data = try? JSONSerialization.data(withJSONObject: database) else { return }
        UserDefaults.standard.set(data, forKey: "setwise.native.workouts")
    }
    private static func localCopy() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: "setwise.native.workouts"),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    private static func merge(local: [String: Any], remote: [String: Any]) -> [String: Any] {
        var result = normalized(remote)
        let localDays = local["days"] as? [String: [String: Any]] ?? [:]
        var days = result["days"] as? [String: Any] ?? [:]
        for (date, localDay) in localDays {
            let remoteDay = days[date] as? [String: Any]
            if remoteDay == nil || (localDay["updatedAt"] as? Double ?? 0) > (remoteDay?["updatedAt"] as? Double ?? 0) { days[date] = localDay }
        }
        result["days"] = days
        let localTemplates = local["templates"] as? [String: Any] ?? [:]
        let remoteTemplates = result["templates"] as? [String: Any] ?? [:]
        let localTimes = local["templateUpdatedAt"] as? [String: Any] ?? [:]
        let remoteTimes = result["templateUpdatedAt"] as? [String: Any] ?? [:]
        var templates = remoteTemplates, times: [String: Any] = remoteTimes
        for (day, template) in localTemplates {
            let localTime = (localTimes[day] as? NSNumber)?.doubleValue ?? 0
            let remoteTime = (remoteTimes[day] as? NSNumber)?.doubleValue ?? 0
            if templates[day] == nil || localTime > remoteTime { templates[day] = template; times[day] = localTimes[day] }
        }
        result["templates"] = templates; result["templateUpdatedAt"] = times
        return result
    }
}

enum APIError: LocalizedError {
    case invalidData, invalidResponse, notSignedIn, server(String)
    var errorDescription: String? {
        switch self { case .invalidData: "Workout data is invalid."; case .invalidResponse: "The server response was invalid."; case .notSignedIn: "Sign in to sync your workouts."; case .server(let message): message }
    }
}
