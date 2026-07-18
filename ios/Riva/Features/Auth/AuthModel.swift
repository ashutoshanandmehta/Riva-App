import Foundation
import Observation

/// App-level authentication state. The user signs in once, at launch; the
/// session persists in the Keychain, so the landing screen reappears only
/// after sign out or a rejected refresh.
@MainActor
@Observable
final class AuthModel {

    enum State: Equatable {
        /// Looking for a stored session at launch.
        case checking
        case signedOut
        case signedIn
    }

    enum Step: Equatable {
        case email
        case code
    }

    private(set) var state: State = .checking
    private(set) var step: Step = .email
    private(set) var isWorking = false
    private(set) var notice: String?
    private(set) var signedInEmail: String?

    var email = ""
    var code = ""

    private let repository: any AuthRepository

    init(repository: any AuthRepository) {
        self.repository = repository
    }

    func start() async {
        guard state == .checking else { return }
        if let session = await repository.currentSession() {
            signedInEmail = session.email
            state = .signedIn
        } else {
            state = .signedOut
        }
    }

    func sendCode() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), address.contains(".") else {
            notice = "Enter the email address you use with Riva."
            return
        }
        email = address
        isWorking = true
        notice = nil
        do {
            try await repository.requestCode(email: address)
            step = .code
            notice = "We emailed a six digit code to \(address)."
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    func verifyCode() async {
        let entered = code.trimmingCharacters(in: .whitespaces)
        guard entered.count >= 6 else {
            notice = "Enter the six digit code from the email."
            return
        }
        isWorking = true
        notice = nil
        do {
            let session = try await repository.verifyCode(email: email, code: entered)
            signedInEmail = session.email
            code = ""
            step = .email
            notice = nil
            state = .signedIn
        } catch {
            notice = error.localizedDescription
        }
        isWorking = false
    }

    func changeEmail() {
        step = .email
        code = ""
        notice = nil
    }

    func signOut() async {
        await repository.signOut()
        signedInEmail = nil
        email = ""
        code = ""
        step = .email
        notice = nil
        state = .signedOut
    }

    /// Called when an API rejects the session mid-use: back to the landing
    /// screen with a gentle explanation.
    func handleExpiredSession() {
        Task {
            await signOut()
            notice = "Your session expired. Sign in again to continue."
        }
    }
}
