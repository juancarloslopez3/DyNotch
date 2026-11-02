import SwiftUI

/// The iPhone's call colors, measured off its Dynamic Island.
enum CallStyle {
    static let green = Color(red: 0.2, green: 0.97, blue: 0.49)
    static let waveform = Color(red: 0.94, green: 0.98, blue: 0.2)
    static let red = Color(red: 1, green: 0.37, blue: 0.34)
    /// A round button's fill, and a button that can't be used now.
    static let button = Color(red: 0.23, green: 0.23, blue: 0.24)
    static let unavailableButton = Color(white: 0.15)
    static let unavailableGlyph = Color(white: 0.43)
    static let avatar = LinearGradient(
        colors: [Color(red: 0.41, green: 0.39, blue: 0.48), Color(red: 0.25, green: 0.22, blue: 0.36)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let addPeople = Color(red: 0.1, green: 0.68, blue: 0.95)
}

/// The call beside the notch, as in the Dynamic Island: a green phone and how long it's been
/// going on the left, its sound on the right.
struct CompactCallView: View {
    @Environment(AppServices.self) private var services
    let notch: CGSize
    var isHovering = false

    var body: some View {
        if let call = services.calls.call {
            WingsLayout(notch: notch) {
                HStack(spacing: 5) {
                    Image(systemName: call.hasEnded ? "phone.down.fill" : "phone.fill")
                        .contentTransition(.symbolEffect(.replace))
                    CallTimeText(call: call, isDetailed: false)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(call.hasEnded ? CallStyle.red : CallStyle.green)
                .lineLimit(1)
                .fixedSize()
            } trailing: {
                CallWaveform(isLive: call.connectedAt != nil && !call.hasEnded)
                    .scaleEffect(isHovering ? 1.15 : 1)
            }
        }
    }
}

/// How long the call has been going: "42s", "11m", "1h" (or "1h 5m" `isDetailed`); nothing
/// while it's being dialled, and frozen once it ends.
struct CallTimeText: View {
    let call: OngoingCall
    let isDetailed: Bool

    var body: some View {
        if let start = call.connectedAt {
            if let end = call.endedAt {
                Text(Self.text(end.timeIntervalSince(start), isDetailed: isDetailed))
            } else {
                TimelineView(.aligned(every: 1)) { context in
                    Text(Self.text(context.date.timeIntervalSince(start), isDetailed: isDetailed))
                }
            }
        }
    }

    static func text(_ elapsed: TimeInterval, isDetailed: Bool) -> String {
        let seconds = max(Int(elapsed), 0)
        if seconds < 60 {
            return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .narrow))
        }
        if seconds < 3600 {
            return Duration.seconds(seconds / 60 * 60).formatted(.units(allowed: [.minutes], width: .narrow))
        }
        let shown = isDetailed ? seconds / 60 * 60 : seconds / 3600 * 3600
        return Duration.seconds(shown).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// A row of dots that moves with the call's sound once DyNotch can hear it (Now Playing's bars
/// follow the music), like the Dynamic Island's.
struct CallWaveform: View {
    @Environment(AppServices.self) private var services
    let isLive: Bool

    private static let count = 13
    private static let dot: CGFloat = 1.8
    private static let pitch: CGFloat = 3
    private static let height: CGFloat = 14
    static let width = CGFloat(count - 1) * pitch + dot

    var body: some View {
        let meter = services.media.meter
        let listens = isLive && services.settings.barsFollowMusic
        TimelineView(.animation(paused: !listens)) { _ in
            let levels = listens ? meter.currentLevels() : nil
            HStack(spacing: Self.pitch - Self.dot) {
                ForEach(0..<Self.count, id: \.self) { index in
                    Capsule()
                        .frame(width: Self.dot, height: Self.dot + (Self.height - Self.dot) * CGFloat(Self.level(index, in: levels)))
                }
            }
        }
        .foregroundStyle(CallStyle.waveform)
        .frame(width: Self.width, height: Self.height)
        .onAppear { meter.barsAppeared() }
        .onDisappear { meter.barsDisappeared() }
    }

    /// The bars' levels spread over the dots: the bass in the middle, as the bars have it.
    private static func level(_ index: Int, in levels: [Float]?) -> Float {
        guard let levels, !levels.isEmpty else { return 0 }
        let band = Int((Float(index) / Float(count - 1) * Float(levels.count - 1)).rounded())
        return levels[band]
    }
}

/// Who the call is with: their initial on the iPhone's gray, or a person without one.
struct CallAvatar: View {
    let call: OngoingCall
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(CallStyle.avatar)
            .overlay {
                if let initial = call.name?.first(where: \.isLetter) {
                    Text(String(initial).uppercased())
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
    }
}

/// The call opened from the notch, as the Dynamic Island's expanded call: who and how long
/// across the top, then the sound output, video, mute, more and end buttons.
struct CallControlsView: View {
    @Environment(AppServices.self) private var services
    let notch: CGSize

    @State private var showsMore = false

    static let contentHeight: CGFloat = 136
    static let cornerRadius: CGFloat = 42
    private static let inset: CGFloat = 20
    private static let buttonSize: CGFloat = 46

    static func width(notch: CGSize) -> CGFloat { max(notch.width + 190, 380) }

    var body: some View {
        let calls = services.calls
        if let call = calls.call {
            ZStack {
                if showsMore {
                    moreMenu(call)
                        .transition(.blurReplace.combined(with: .scale(0.95)))
                } else {
                    VStack(spacing: 16) {
                        header(call)
                        buttons(call)
                    }
                    .transition(.blurReplace)
                }
            }
            .padding([.horizontal, .bottom], Self.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, notch.height)
            .animation(.notchQuick, value: showsMore)
        }
    }

    private func header(_ call: OngoingCall) -> some View {
        HStack(spacing: 12) {
            CallAvatar(call: call, size: Self.buttonSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(call.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Group {
                    if call.hasEnded {
                        Text("Call Ended").foregroundStyle(CallStyle.red)
                    } else if call.isOnHold {
                        Text("On Hold")
                    } else if call.connectedAt == nil {
                        Text("Calling…")
                    } else {
                        CallTimeText(call: call, isDetailed: true)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                services.calls.showApp()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(CallButtonPress())
            .help("Call Info")
        }
    }

    private func buttons(_ call: OngoingCall) -> some View {
        let calls = services.calls
        let microphone = calls.microphone
        let output = calls.outputs.current
        return HStack(spacing: 0) {
            Menu {
                ForEach(calls.outputs.all) { device in
                    Toggle(isOn: Binding(get: { output == device }, set: { _ in calls.outputs.select(device) })) {
                        Label(device.name, systemImage: device.symbol)
                    }
                }
            } label: {
                CallButtonFace(
                    symbol: output?.symbol ?? "speaker.wave.2.fill",
                    glyph: output?.isSpeaker != false ? .black : .white,
                    fill: output?.isSpeaker != false ? .white : CallStyle.button
                )
            }
            .menuStyle(.button)
            .buttonStyle(CallButtonPress())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Audio Output")
            Spacer(minLength: 0)
            Button {
                calls.showApp()
            } label: {
                CallButtonFace(
                    symbol: call.isVideo ? "video.fill" : "video.slash.fill",
                    glyph: call.isVideo ? .white : CallStyle.unavailableGlyph,
                    fill: call.isVideo ? CallStyle.button : CallStyle.unavailableButton
                )
            }
            .buttonStyle(CallButtonPress())
            .disabled(!call.isVideo || call.hasEnded)
            .help("Video")
            Spacer(minLength: 0)
            Button {
                calls.toggleMute()
            } label: {
                CallButtonFace(
                    symbol: microphone.isMuted ? "mic.slash.fill" : "mic.fill",
                    glyph: microphone.canMute ? (microphone.isMuted ? CallStyle.red : .white) : CallStyle.unavailableGlyph,
                    fill: microphone.canMute ? CallStyle.button : CallStyle.unavailableButton
                )
            }
            .buttonStyle(CallButtonPress())
            .disabled(!microphone.canMute || call.hasEnded)
            .help(microphone.isMuted ? "Unmute" : "Mute")
            Spacer(minLength: 0)
            Button {
                showsMore = true
            } label: {
                CallButtonFace(symbol: "ellipsis", glyph: .white, fill: CallStyle.button)
            }
            .buttonStyle(CallButtonPress())
            .disabled(call.hasEnded)
            .help("More")
            Spacer(minLength: 0)
            Button {
                calls.end()
            } label: {
                CallButtonFace(symbol: "phone.down.fill", glyph: .white, fill: CallStyle.red)
            }
            .buttonStyle(CallButtonPress())
            .disabled(call.hasEnded)
            .help("End Call")
        }
    }

    /// The more button's options over the call, as on the iPhone: on glass, each with its
    /// round picture. A click anywhere else on them goes back to the call.
    private func moreMenu(_ call: OngoingCall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            moreItem("Add People") {
                Circle()
                    .fill(CallStyle.addPeople)
                    .overlay {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
            }
            moreItem("Contact Card") {
                CallAvatar(call: call, size: 40)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius - Self.inset + 10))
        .contentShape(.rect)
        .onTapGesture { showsMore = false }
        .padding(.top, 4)
        .padding(.horizontal, -10)
        .padding(.bottom, -10)
    }

    private func moreItem(_ title: LocalizedStringKey, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            showsMore = false
            services.calls.showApp()
        } label: {
            HStack(spacing: 14) {
                icon()
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .contentShape(.rect)
        }
        .buttonStyle(CallButtonPress())
    }
}

/// A round call button: its symbol on a fill.
struct CallButtonFace: View {
    let symbol: String
    let glyph: Color
    let fill: Color

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(glyph)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 46, height: 46)
            .contentShape(.circle)
    }
}

/// Lights up under the pointer and gives under a click, as the notch's other buttons.
struct CallButtonPress: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : isHovered && isEnabled ? 0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.notchQuick, value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
