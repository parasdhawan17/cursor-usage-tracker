import Foundation
import IOKit.pwr_mgt

@MainActor
enum CaffeinateSettings {
    private static let userDefaultsKey = "caffeinateEnabled"
    private static var assertionID: IOPMAssertionID = 0

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func restoreStoredPreference() throws {
        guard isEnabled else { return }
        try startAssertion()
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try startAssertion()
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
        } else {
            stopAssertion()
            UserDefaults.standard.set(false, forKey: userDefaultsKey)
        }
    }

    private static func startAssertion() throws {
        guard assertionID == 0 else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Cursor Usage is keeping this Mac awake" as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            throw CaffeinateError.assertionFailed(result)
        }

        assertionID = newAssertionID
    }

    private static func stopAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    enum CaffeinateError: LocalizedError {
        case assertionFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .assertionFailed(let code):
                return "Could not keep this Mac awake. IOKit returned \(code)."
            }
        }
    }
}
