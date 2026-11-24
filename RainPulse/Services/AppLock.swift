import SwiftUI
import LocalAuthentication

/// Optional Face ID / Touch ID / passcode lock, plus a privacy screen that hides
/// your places in the app switcher.
@MainActor
final class AppLock: ObservableObject {
    @AppStorage("security.appLock") var enabled = false
    @Published var isLocked = false
    @Published var isObscured = false

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    func sceneChanged(to phase: ScenePhase) {
        guard enabled, !AppConfig.isUITest else { isObscured = false; return }
        switch phase {
        case .background:
            isLocked = true
            isObscured = true
        case .inactive:
            isObscured = true
        case .active:
            isObscured = false
            if isLocked { unlock() }
        @unknown default: break
        }
    }

    func lockNowIfEnabled() {
        if enabled && !AppConfig.isUITest { isLocked = true; unlock() }
    }

    func unlock() {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = String(localized: "Use Passcode")
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false   // no passcode set on device: nothing to unlock with
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock RainPulse")) { ok, _ in
            Task { @MainActor in if ok { self.isLocked = false } }
        }
    }

    /// Turning the lock on requires proving you can unlock.
    func setEnabled(_ on: Bool) {
        guard on else { enabled = false; return }
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Turn on app lock")) { ok, _ in
            Task { @MainActor in self.enabled = ok }
        }
    }
}

struct LockScreen: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            SkyBackground(colors: Theme.sky(code: 0, isNight: true))
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.white)
                Text("RainPulse is locked").font(.title2.weight(.semibold)).foregroundStyle(.white)
                if lock.isLocked {
                    Button("Unlock with \(lock.biometryName)") { lock.unlock() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
