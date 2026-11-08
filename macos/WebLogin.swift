import AppKit
import AuthenticationServices

@MainActor
final class WebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var deadline: Task<Void, Never>?
    private var anchor: NSWindow?
    private var sessionID = UUID()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? NSWindow()
    }
    func authenticate(url: URL, redirect: URL, anchor: NSWindow) async throws -> URL {
        try Task.checkCancellation()
        guard session == nil else { throw CareLinkError.authentication }
        self.anchor = anchor
        let identifier = UUID()
        sessionID = identifier
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url:url, callbackURLScheme:redirect.scheme) { [weak self] url, error in
                    Task { @MainActor in
                        if let url { self?.finish(.success(url), identifier:identifier) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(.failure(CareLinkError.cancelled), identifier:identifier)
                        } else { self?.finish(.failure(CareLinkError.authentication), identifier:identifier) }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                if !session.start() { finish(.failure(CareLinkError.authentication), identifier:identifier); return }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds:300_000_000_000) } catch { return }
                    self?.cancel(identifier:identifier)
                }
            }
        }, onCancel: { Task { @MainActor in self.cancel(identifier:identifier) } })
    }
    func cancel(identifier: UUID? = nil) {
        if let identifier, identifier != sessionID { return }
        let current = session
        finish(.failure(CareLinkError.cancelled), identifier:sessionID)
        current?.cancel()
    }
    private func finish(_ result: Result<URL,Error>, identifier: UUID) {
        guard identifier == sessionID, let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        session = nil; anchor = nil
        continuation.resume(with:result)
    }
}
