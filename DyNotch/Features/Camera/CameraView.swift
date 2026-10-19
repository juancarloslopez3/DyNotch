import AVFoundation
import SwiftUI

/// Owns the capture session on a private queue. It runs only while the Camera tab is
/// on screen, so the green camera light turns off as soon as the notch closes.
nonisolated final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.dynotch.camera")
    private var isConfigured = false

    func start() {
        queue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first { $0.deviceType == .builtInWideAngleCamera } ?? AVCaptureDevice.default(for: .video)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        isConfigured = true
    }
}

struct CameraTabView: View {
    @Environment(AppServices.self) private var services
    let model: NotchViewModel
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        let isLarge = services.settings.cameraSize == .large
        // The picture grows over the text beside it, which fades away under it.
        ZStack(alignment: .topLeading) {
            if !isLarge {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Mirror", systemImage: "camera.metering.center.weighted")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Click the picture to see yourself as others do. Video stays on your Mac and the camera turns off when the notch closes.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, Self.standardWidth + 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }

            Group {
                switch status {
                case .authorized:
                    Mirror(session: services.camera.session, settings: services.settings)
                        .onAppear { services.camera.start() }
                        .onDisappear { services.camera.stop() }
                case .notDetermined:
                    placeholder(symbol: "web.camera", text: "See yourself before a call", button: "Allow Camera") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            status = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                    }
                default:
                    placeholder(symbol: "video.slash", text: "Camera access is off", button: "Open Settings") {
                        services.permissions.openSettings(.camera)
                    }
                }
            }
            .frame(maxWidth: isLarge ? .infinity : Self.standardWidth, maxHeight: .infinity)
        }
    }

    /// The picture's width beside the text; a large one takes the whole tab.
    private static let standardWidth: CGFloat = 310

    private func placeholder(symbol: String, text: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Button(button, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// The camera's picture, mirrored or as others see you. Clicking it turns it over to the other,
/// like a Home card. While the pointer is over it, buttons in its corner grow or shrink it and
/// say which way round it is.
private struct Mirror: View {
    let session: AVCaptureSession
    let settings: AppSettings
    @State private var isHovering = false

    var body: some View {
        let isMirrored = settings.cameraMirrored
        let isLarge = settings.cameraSize == .large
        TurningPicture(session: session, angle: isMirrored ? 0 : 180)
            .contentShape(.rect(cornerRadius: 20))
            .onTapGesture(perform: flip)
            .accessibilityElement()
            .accessibilityLabel("Camera")
            .accessibilityValue(isMirrored ? "Mirrored" : "As others see you")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, flip)
            .accessibilityActions {
                Button(isLarge ? "Smaller Picture" : "Larger Picture", action: resize)
            }
            // The top left corner stays put as the picture grows, so the size button is still
            // under the pointer to shrink it again.
            .overlay(alignment: .topLeading) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: resize) {
                            Image(systemName: isLarge ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 28, height: 28)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .help(isLarge ? "Smaller Picture" : "Larger Picture")

                        Button(action: flip) {
                            Label(isMirrored ? "Mirrored" : "As Others See You", systemImage: "arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .help("Flip the Picture")
                    }
                    .foregroundStyle(.white)
                }
                .padding(10)
                .opacity(isHovering ? 1 : 0)
            }
            .onHover { hovering in
                withAnimation(.notchQuick) { isHovering = hovering }
            }
    }

    private func flip() {
        withAnimation(.flip) { settings.cameraMirrored.toggle() }
    }

    /// The notch springs to its new size, and the picture with it.
    private func resize() {
        settings.cameraSize = settings.cameraSize == .large ? .standard : .large
    }
}

/// The picture `angle` degrees into a turn about its vertical axis: 0 shows it mirrored, 180 as
/// others see you. SwiftUI animates the angle, and the layer follows it frame by frame.
private struct TurningPicture: View, Animatable {
    let session: AVCaptureSession
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        CameraPreview(session: session, angle: angle)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let angle: Double

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.angle = angle
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        /// The rounded card the picture is on, which turns over, and a shade on it that darkens
        /// it as it goes edge-on.
        private let card = CALayer()
        private let shade = CALayer()
        private var sessionObserver: NSObjectProtocol?

        var angle: Double = 0 {
            didSet {
                if angle != oldValue { turn() }
            }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            card.backgroundColor = NSColor.black.cgColor
            card.cornerRadius = 20
            card.cornerCurve = .continuous
            card.masksToBounds = true
            shade.backgroundColor = NSColor.black.cgColor
            shade.opacity = 0
            card.addSublayer(previewLayer)
            card.addSublayer(shade)
            layer?.addSublayer(card)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// Clicks go to SwiftUI, which turns the picture over.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.bounds = bounds
            card.position = CGPoint(x: bounds.midX, y: bounds.midY)
            previewLayer.frame = card.bounds
            shade.frame = card.bounds
            CATransaction.commit()
            turn()
            mirror()
        }

        /// The first time the camera starts, its connection to the layer only comes once the
        /// picture is already up.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let sessionObserver {
                NotificationCenter.default.removeObserver(sessionObserver)
                self.sessionObserver = nil
            }
            guard window != nil else { return }
            sessionObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification,
                object: previewLayer.session,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.mirror() }
            }
        }

        /// At rest the picture shows as a mirror does, so turned over it shows as others see you.
        private func mirror() {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        /// Turns the card `angle` degrees about its vertical axis, in perspective. Like a Home
        /// card's, it sinks back a little and darkens as it goes edge-on.
        private func turn() {
            let radians = angle * .pi / 180
            let edgeOn = abs(sin(radians))
            let scale = 1 - 0.06 * edgeOn
            var perspective = CATransform3DIdentity
            perspective.m34 = -0.3 / max(bounds.width, bounds.height, 1)
            let transform = CATransform3DConcat(
                CATransform3DConcat(CATransform3DMakeScale(scale, scale, scale), CATransform3DMakeRotation(radians, 0, 1, 0)),
                perspective
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.transform = transform
            shade.opacity = Float(0.35 * edgeOn)
            CATransaction.commit()
        }
    }
}
