import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()
    var onToggleSet: ((String, Int, Bool) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(day: String, startedAt: Date?, exercises: [WorkoutExercise]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let rows: [[String: Any]] = exercises.map { exercise in
            ["id": exercise.id, "name": exercise.name, "sets": exercise.sets.map { ["reps": $0.reps, "weight": $0.weight, "done": $0.done] }]
        }
        var context: [String: Any] = ["day": day, "exercises": rows]
        if let startedAt { context["startedAt"] = startedAt }
        do { try WCSession.default.updateApplicationContext(context) } catch { print("Watch sync failed: \(error)") }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["action"] as? String == "toggleSet",
              let exerciseID = userInfo["exerciseID"] as? String,
              let setIndex = userInfo["setIndex"] as? Int,
              let done = userInfo["done"] as? Bool else { return }
        Task { @MainActor in onToggleSet?(exerciseID, setIndex, done) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
