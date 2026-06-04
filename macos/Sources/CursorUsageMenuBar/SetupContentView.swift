import SwiftUI

struct SetupContentView: View {
    @Binding var tokenInput: String
    var tokenFieldFocusToken: Int
    let saveError: String?
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: (() -> Void)?
    let onRemoveToken: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect your account", systemImage: "key.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Paste your Cursor session cookie so this app can read usage from the dashboard API.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            instructionsCard

            VStack(alignment: .leading, spacing: 6) {
                Text("Session token")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TokenInputField(text: $tokenInput, focusToken: tokenFieldFocusToken)
                    .frame(height: 24)
                HStack(spacing: 8) {
                    Button("Paste from clipboard") {
                        if let pasted = PasteboardToken.readString() {
                            tokenInput = pasted
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Text("or press ⌘V")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(light: "#FF3B30", dark: "#FF453A"))
            }

            HStack(spacing: 8) {
                Button(action: onSave) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save & connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let onRemoveToken {
                Button("Remove saved token", role: .destructive, action: onRemoveToken)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }

            Link("Open usage dashboard", destination: URL(string: "https://cursor.com/dashboard/usage")!)
                .font(.system(size: 11))
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to find the token")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            instructionRow(1, "Open the usage dashboard in your browser.")
            instructionRow(2, "DevTools → Application → Cookies → cursor.com")
            instructionRow(3, "Copy WorkosCursorSessionToken and paste above.")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sectionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.sectionBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
