import AppKit
import SwiftUI

struct SetupContentView: View {
    @Binding var tokenInput: String
    var tokenFieldFocusToken: Int
    let saveError: String?
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: (() -> Void)?
    let onRemoveToken: (() -> Void)?

    private static let dashboardURL = URL(string: "https://cursor.com/dashboard/usage")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            stepsCard
            pasteSection

            if let saveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                    Text(saveError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.destructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            saveActions

            if let onRemoveToken {
                Button("Remove saved token", role: .destructive, action: onRemoveToken)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }

            privacyNote
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                Image(systemName: "key.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your account")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("One-time setup. Follow the steps below, then paste your session token.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderLabel(title: "How to get your token")

            InsetGroupedCard {
                VStack(alignment: .leading, spacing: 14) {
                    setupStep(
                        number: 1,
                        title: "Open the usage dashboard",
                        detail: "Sign in at cursor.com if you are not already."
                    ) {
                        Button {
                            NSWorkspace.shared.open(Self.dashboardURL)
                        } label: {
                            Label("Open Dashboard", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    setupStep(
                        number: 2,
                        title: "Open developer tools",
                        detail: "Press ⌥⌘I in Chrome, or right-click the page and choose Inspect."
                    )

                    setupStep(
                        number: 3,
                        title: "Open the Cookies panel",
                        detail: "In the top bar, choose Application → Storage → Cookies → cursor.com."
                    )

                    setupStep(
                        number: 4,
                        title: "Copy the session token",
                        detail: nil
                    ) {
                        tokenNameHint
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var tokenNameHint: some View {
        HStack(spacing: 4) {
            Text("Copy the")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text("WorkosCursorSessionToken")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("value.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderLabel(title: "Paste your token")

            VStack(alignment: .leading, spacing: 10) {
                TokenInputField(text: $tokenInput, focusToken: tokenFieldFocusToken)
                    .frame(height: 28)

                HStack(spacing: 8) {
                    Button {
                        if let pasted = PasteboardToken.readString() {
                            tokenInput = pasted
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("or ⌘V")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var saveActions: some View {
        HStack(spacing: 8) {
            Button(action: onSave) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSaving ? "Connecting…" : "Save & connect")
                }
                .frame(maxWidth: .infinity)
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
    }

    private var privacyNote: some View {
        Label("Stored locally on this Mac only", systemImage: "lock.fill")
            .font(.system(size: 10))
            .foregroundStyle(Theme.textTertiary)
    }


    private func setupStep<Accessory: View>(
        number: Int,
        title: String,
        detail: String?,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stepBadge(number)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accessory()
            }
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Theme.accent, in: Circle())
    }
}
