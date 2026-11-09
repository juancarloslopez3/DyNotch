import SwiftUI

/// The window `UpdateController` shows when a new version is out.
struct UpdateView: View {
    static let width: CGFloat = 480

    let controller: UpdateController

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 10) {
                Text("A new version of DyNotch is available")
                    .font(.headline)
                if let release = controller.release {
                    Text("DyNotch \(release.version) is out. You have version \(controller.currentVersion).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !release.notes.isEmpty {
                        notes(release.notes)
                    }
                }
                footer
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: Self.width)
    }

    private func notes(_ markdown: String) -> some View {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let notes = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return ScrollView {
            Text(notes)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(height: 130)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private var footer: some View {
        switch controller.phase {
        case .available:
            HStack {
                Button("Release Notes", action: controller.openReleasePage)
                Spacer()
                Button("Later", action: controller.close)
                    .keyboardShortcut(.cancelAction)
                if controller.canInstallInPlace {
                    Button("Install and Restart", action: controller.installAndRestart)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Download", action: controller.downloadManually)
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .downloading(let fraction):
            HStack {
                ProgressView(value: fraction) {
                    Text("Downloading…")
                }
                Button("Cancel", action: controller.close)
                    .keyboardShortcut(.cancelAction)
            }
        case .installing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Installing… DyNotch will restart by itself.")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Download Manually", action: controller.downloadManually)
                    Spacer()
                    Button("Later", action: controller.close)
                        .keyboardShortcut(.cancelAction)
                    Button("Try Again", action: controller.installAndRestart)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
