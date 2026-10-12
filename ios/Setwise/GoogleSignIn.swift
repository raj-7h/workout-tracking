import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class GoogleSignIn: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var isSigningIn = false
    @Published var errorMessage: String?
    private var session: ASWebAuthenticationSession?
    private let baseURL = URL(string: "https://workout-tracking-ebon.vercel.app")!

    func signIn(onToken: @escaping (String) -> Void) {
        var components = URLComponents(url: baseURL.appending(path: "/api/auth/start"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "native", value: "1")]
        guard let url = components.url else { errorMessage = "Couldn’t start Google sign-in."; return }
        isSigningIn = true
        let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "setwise") { [weak self] callback, error in
            Task { @MainActor in
                self?.isSigningIn = false
                if let error { self?.errorMessage = error.localizedDescription; return }
                guard let callback, let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      let handoff = parts.queryItems?.first(where: { $0.name == "handoff" })?.value else {
                    self?.errorMessage = "Google sign-in didn’t return a Setwise session."; return
                }
                do {
                    let token = try await self?.exchange(handoff: handoff)
                    guard let token else { throw APIError.invalidResponse }
                    onToken(token)
                } catch {
                    self?.errorMessage = "Sign-in couldn’t finish: \(error.localizedDescription)"
                }
            }
        }
        auth.presentationContextProvider = self
        auth.prefersEphemeralWebBrowserSession = false
        session = auth
        auth.start()
    }

    private func exchange(handoff: String) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/auth/native-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["handoff": handoff])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = result["session"] as? String else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError.server(message ?? "The sign-in handoff was rejected.")
        }
        return token
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow ?? ASPresentationAnchor()
    }
}
