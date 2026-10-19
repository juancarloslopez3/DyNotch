import SwiftUI

/// Rows with each permission's status and a Grant button. Used in onboarding and Settings.
struct PermissionsList: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let center = services.permissions
        ForEach(PermissionKind.allCases) { kind in
            PermissionRow(
                kind: kind,
                state: center.state(kind),
                progress: center.isAllowingAll ? (center.allowingAllKind == kind ? .asking : .waiting) : nil,
                skip: center.skipAllowAllKind
            ) {
                Task { await center.request(kind) }
            }
        }
        .task {
            // Permissions change in System Settings; poll while visible.
            while !Task.isCancelled {
                center.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

private struct PermissionRow: View {
    /// Where Allow All is in relation to this row.
    enum Progress { case asking, waiting }

    let kind: PermissionKind
    let state: PermissionState
    let progress: Progress?
    let skip: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.tint, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.title).font(.body.weight(.medium))
                    if kind.isRequired {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: .capsule)
                            .foregroundStyle(.orange)
                    }
                }
                Text(kind.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if progress == .asking, state != .granted {
                ProgressView()
                    .controlSize(.small)
                Button("Skip", action: skip)
            } else {
                switch state {
                case .granted:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                case .denied:
                    Button(kind.grantTitle(state), action: action)
                        .disabled(progress != nil)
                case .notDetermined:
                    Button(kind.grantTitle(state), action: action)
                        .buttonStyle(.borderedProminent)
                        .disabled(progress != nil)
                }
            }
        }
        .animation(.default, value: state)
        .animation(.default, value: progress)
    }
}

/// The notice for a permission the setting above it needs, with the button that asks for it
/// (or opens its list in System Settings). Shows nothing once it's allowed.
struct PermissionNotice: View {
    @Environment(AppServices.self) private var services
    let kind: PermissionKind
    let message: LocalizedStringResource

    init(_ kind: PermissionKind, _ message: LocalizedStringResource) {
        self.kind = kind
        self.message = message
    }

    var body: some View {
        let center = services.permissions
        let state = center.state(kind)
        if state != .granted {
            SettingsNotice(message, button: kind.grantTitle(state)) { Task { await center.request(kind) } }
        }
    }
}

/// A row that says why the setting above it can't do its job yet, with the button that fixes it.
struct SettingsNotice: View {
    let message: LocalizedStringResource
    let button: String
    let action: () -> Void

    init(_ message: LocalizedStringResource, button: String, action: @escaping () -> Void) {
        self.message = message
        self.button = button
        self.action = action
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer()
            // The message's layout priority would otherwise squeeze the title down to "…".
            Button(button, action: action)
                .fixedSize()
        }
    }
}

/// Allow All, which asks for every permission that isn't allowed yet in turn, or Stop while it
/// does. `done` runs once it's been through them all.
struct AllowAllButton: View {
    @Environment(AppServices.self) private var services
    var isProminent = true
    var done: () -> Void = {}

    var body: some View {
        let center = services.permissions
        if center.isAllowingAll {
            Button("Stop", action: center.stopAllowAll)
        } else {
            let button = Button("Allow All") { center.allowAll(done: done) }
                .disabled(center.allGranted)
            if isProminent {
                button.buttonStyle(.glassProminent)
            } else {
                button
            }
        }
    }
}

extension PermissionCenter {
    var allGranted: Bool { PermissionKind.allCases.allSatisfy { state($0) == .granted } }
}

extension PermissionKind {
    /// What the button that grants it says: the lists only System Settings can change, and
    /// anything turned down, open there.
    func grantTitle(_ state: PermissionState) -> String {
        opensSettings(state) ? String(localized: "Open Settings") : String(localized: "Allow")
    }
}
