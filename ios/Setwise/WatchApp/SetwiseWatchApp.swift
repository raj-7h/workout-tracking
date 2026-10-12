import SwiftUI
import WatchConnectivity

@main
struct SetwiseWatchApp: App {
    var body: some Scene { WindowGroup { WatchWorkoutView() } }
}

struct WatchWorkoutView: View {
    @StateObject private var model = WatchWorkoutModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.exercises.isEmpty {
                    ContentUnavailableView("Open Setwise on iPhone", systemImage: "iphone.and.arrow.forward", description: Text("Your selected workout will appear here when your Apple Watch is paired."))
                } else {
                    List {
                        if let start = model.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Label(Duration.seconds(context.date.timeIntervalSince(start)).formatted(.time(pattern: .minuteSecond)), systemImage: "timer")
                                    .font(.headline).foregroundStyle(.green)
                            }
                        }
                        ForEach(model.exercises) { exercise in
                            Section(exercise.name) {
                                ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                                    Button { model.toggle(exerciseID: exercise.id, index: index) } label: {
                                        HStack {
                                            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                                            Text("Set \(index + 1)")
                                            Spacer(minLength: 4)
                                            Text("\(set.reps.isEmpty ? "—" : set.reps) × \(set.weight.isEmpty ? "—" : set.weight) kg")
                                                .foregroundStyle(.secondary)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(model.day.isEmpty ? "Setwise" : model.day)
        }
    }
}

@MainActor
final class WatchWorkoutModel: NSObject, ObservableObject {
    struct Exercise: Identifiable { var id: String; var name: String; var sets: [Set] }
    struct Set { var reps: String; var weight: String; var done: Bool }
    @Published var day = ""
    @Published var startedAt: Date?
    @Published var exercises: [Exercise] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    func toggle(exerciseID: String, index: Int) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseID }), exercises[e].sets.indices.contains(index) else { return }
        exercises[e].sets[index].done.toggle()
        let set = exercises[e].sets[index]
        WCSession.default.transferUserInfo(["action": "toggleSet", "exerciseID": exerciseID, "setIndex": index, "done": set.done])
    }

    private func apply(_ context: [String: Any]) {
        day = context["day"] as? String ?? ""
        startedAt = context["startedAt"] as? Date
        exercises = (context["exercises"] as? [[String: Any]] ?? []).map { row in
            Exercise(id: row["id"] as? String ?? UUID().uuidString, name: row["name"] as? String ?? "Exercise", sets: (row["sets"] as? [[String: Any]] ?? []).map { Set(reps: $0["reps"] as? String ?? "", weight: $0["weight"] as? String ?? "", done: $0["done"] as? Bool ?? false) })
        }
    }
}

extension WatchWorkoutModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in apply(applicationContext) }
    }
}
