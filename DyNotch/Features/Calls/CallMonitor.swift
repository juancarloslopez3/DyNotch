import AppKit
import Observation
import OSLog

/// A phone or FaceTime call going on on this Mac.
struct OngoingCall: Equatable {
    let id: UUID
    /// Who it's with, as the call shows them: a name or a number; `nil` until it can be read.
    var name: String?
    /// The app that has the call: FaceTime, Phone, or another that reports its calls to CallKit.
    var appBundleID: String?
    var isOutgoing: Bool
    var isVideo: Bool
    var isOnHold: Bool
    /// When it was answered; `nil` while it's still being dialled.
    var connectedAt: Date?
    /// When it ended. It stays a moment saying so, as the Dynamic Island does, then goes.
    var endedAt: Date?

    var hasEnded: Bool { endedAt != nil }

    /// How it's named when the person can't be: after its app ("FaceTime"), or just a call.
    var title: String {
        if let name, !name.isEmpty { return name }
        if let appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return String(localized: "Call")
    }
}

/// Follows the calls on this Mac through CallKit and keeps the one to show in the notch, with
/// what its buttons there need: the microphone's mute and the sound output.
@Observable
final class CallMonitor {
    /// The call to show: the one going on, or for a moment after it ends, the one that ended.
    private(set) var call: OngoingCall?
    let microphone = CallMicrophone()
    let outputs = AudioOutputs()

    /// How long an ended call stays, saying so.
    static let endedDuration: Duration = .seconds(2)

    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private let observer = CallKitObserver()
    @ObservationIgnored private var systemCall: OngoingCall? {
        didSet { refresh() }
    }
    /// When each call was first seen connected, since CallKit doesn't say when it was answered.
    @ObservationIgnored private var connectedDates: [UUID: Date] = [:]
    @ObservationIgnored private var endTask: Task<Void, Never>?

    #if DEBUG
    /// A made-up call (`swift scripts/notch.swift call`), shown over any real one.
    var simulated: OngoingCall? {
        didSet { refresh() }
    }
    #endif

    func start(services: AppServices) {
        self.services = services
        microphone.start()
        outputs.start()
        observer.onChange = { [weak self] calls in self?.update(calls) }
        observer.start()
        // A microphone muted for a call before DyNotch last quit comes back on, unless that
        // call is still going. CallKit takes a moment to say.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, systemCall == nil else { return }
            microphone.releaseMute()
        }
    }

    func toggleMute() {
        microphone.setMuted(!microphone.isMuted)
    }

    /// Hangs up through CallKit. Where it won't take the request (it may keep that to the
    /// call's own app), the app comes forward with its own end button.
    func end() {
        #if DEBUG
        if let simulated, !simulated.hasEnded {
            var ended = simulated
            ended.endedAt = .now
            self.simulated = ended
            Task { [weak self] in
                try? await Task.sleep(for: Self.endedDuration)
                if self?.simulated?.id == ended.id { self?.simulated = nil }
            }
            return
        }
        #endif
        guard let call = systemCall, !call.hasEnded else { return }
        observer.requestEnd(call.id) { [weak self] ended in
            if !ended { self?.showApp() }
        }
    }

    /// Brings the call's app forward, where the call has the rest of its controls.
    func showApp() {
        guard let bundleID = call?.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func refresh() {
        #if DEBUG
        call = simulated ?? systemCall
        #else
        call = systemCall
        #endif
        let isTalking = call?.connectedAt != nil && call?.hasEnded == false
        services?.media.meter.update(onCall: isTalking && services?.settings.barsFollowMusic == true)
    }

    private func update(_ calls: [CallKitCall]) {
        for call in calls where call.hasConnected && connectedDates[call.id] == nil {
            connectedDates[call.id] = .now
        }
        connectedDates = connectedDates.filter { id, _ in calls.contains { $0.id == id && !$0.hasEnded } }
        // Not one still ringing (macOS shows that itself), nor one on the iPhone that this Mac
        // merely hears about.
        let live = calls.filter { !$0.hasEnded && $0.isOnThisMac && ($0.hasConnected || $0.isOutgoing) }
        guard let shown = live.first(where: { !$0.isOnHold }) ?? live.first else {
            if let ending = systemCall, !ending.hasEnded { finish(ending) }
            return
        }
        endTask?.cancel()
        endTask = nil
        let previous = systemCall?.id == shown.id ? systemCall : nil
        systemCall = OngoingCall(
            id: shown.id,
            name: previous?.name,
            appBundleID: shown.appBundleID,
            isOutgoing: shown.isOutgoing,
            isVideo: shown.isVideo,
            isOnHold: shown.isOnHold,
            connectedAt: connectedDates[shown.id]
        )
    }

    /// The call is over: it says so for a moment, then goes.
    private func finish(_ call: OngoingCall) {
        var ended = call
        ended.endedAt = .now
        systemCall = ended
        // A muted microphone would stay muted for whatever comes next.
        microphone.releaseMute()
        endTask = Task { [weak self] in
            try? await Task.sleep(for: Self.endedDuration)
            guard !Task.isCancelled else { return }
            self?.systemCall = nil
        }
    }
}

/// What CallKit says about a call.
struct CallKitCall {
    let id: UUID
    let providerIdentifier: String?
    let isOutgoing: Bool
    let isOnHold: Bool
    let hasConnected: Bool
    let hasEnded: Bool
    let isVideo: Bool
    /// Its sound is on this Mac, rather than on an iPhone nearby.
    let isOnThisMac: Bool

    /// The app that has the call. CallKit names Apple's own by their call providers.
    var appBundleID: String? {
        guard let providerIdentifier else { return nil }
        if providerIdentifier.localizedCaseInsensitiveContains("facetime") { return "com.apple.FaceTime" }
        if providerIdentifier.localizedCaseInsensitiveContains("telephony") { return "com.apple.mobilephone" }
        return providerIdentifier
    }
}

/// CallKit's call observer. macOS has it, though its SDK keeps it to iOS and Mac Catalyst
/// apps, so it's reached by name. It hears of FaceTime calls and the iPhone's calls on this Mac
/// without asking for any permission, and only connects while there is a call.
final class CallKitObserver: NSObject {
    var onChange: (([CallKitCall]) -> Void)?

    private var observer: NSObject?
    private static let logger = Logger(subsystem: "app.dynotch", category: "Calls")

    func start() {
        guard observer == nil else { return }
        dlopen("/System/Library/Frameworks/CallKit.framework/CallKit", RTLD_LAZY)
        guard let type = NSClassFromString("CXCallObserver") as? NSObject.Type else {
            Self.logger.error("CallKit has no call observer")
            return
        }
        if let delegate = objc_getProtocol("CXCallObserverDelegate") {
            class_addProtocol(Self.self, delegate)
        }
        let observer = type.init()
        let setDelegate = NSSelectorFromString("setDelegate:queue:")
        guard observer.responds(to: setDelegate) else {
            Self.logger.error("CallKit's call observer takes no delegate")
            return
        }
        observer.perform(setDelegate, with: self, with: DispatchQueue.main)
        self.observer = observer
        report()
    }

    /// Asks CallKit to end the call; `completion` says whether it did.
    func requestEnd(_ id: UUID, completion: @escaping (Bool) -> Void) {
        guard let controllerType = NSClassFromString("CXCallController") as? NSObject.Type,
              let action = Self.make("CXEndCallAction", "initWithCallUUID:", with: id as NSUUID),
              let transaction = Self.make("CXTransaction", "initWithAction:", with: action)
        else { return completion(false) }
        let controller = controllerType.init()
        let request: @convention(block) (NSError?) -> Void = { error in
            DispatchQueue.main.async {
                if let error {
                    Self.logger.error("CallKit didn't end the call: \(error, privacy: .public)")
                }
                // Keeps the controller until it has answered.
                _ = controller
                completion(error == nil)
            }
        }
        controller.perform(NSSelectorFromString("requestTransaction:completion:"), with: transaction, with: request)
    }

    /// `[[className alloc] initializer argument]`, for CallKit's classes that the SDK hides.
    private static func make(_ className: String, _ initializer: String, with argument: AnyObject) -> NSObject? {
        guard let type = NSClassFromString(className) as? NSObject.Type,
              type.instancesRespond(to: NSSelectorFromString(initializer))
        else { return nil }
        // `init` takes over the object `alloc` returned and returns its own.
        let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        return allocated.perform(NSSelectorFromString(initializer), with: argument)?.takeRetainedValue() as? NSObject
    }

    @objc(callObserver:callChanged:)
    nonisolated func callObserver(_ observer: NSObject, callChanged call: NSObject) {
        MainActor.assumeIsolated { report() }
    }

    private func report() {
        let calls = (observer?.value(forKey: "calls") as? [NSObject] ?? []).compactMap(Self.call)
        Self.logger.log("Calls: \(calls.map { "\($0.providerIdentifier ?? "?") outgoing \($0.isOutgoing) connected \($0.hasConnected) ended \($0.hasEnded) held \($0.isOnHold) video \($0.isVideo) here \($0.isOnThisMac)" }, privacy: .public)")
        onChange?(calls)
    }

    private static func call(_ object: NSObject) -> CallKitCall? {
        guard let id = value(object, "UUID") as? UUID else { return nil }
        func flag(_ getter: String) -> Bool? { (value(object, getter) as? NSNumber)?.boolValue }
        return CallKitCall(
            id: id,
            providerIdentifier: value(object, "providerIdentifier") as? String,
            isOutgoing: flag("isOutgoing") ?? false,
            isOnHold: flag("isOnHold") ?? false,
            hasConnected: flag("hasConnected") ?? false,
            hasEnded: flag("hasEnded") ?? false,
            isVideo: flag("isVideo") ?? false,
            isOnThisMac: flag("isEndpointOnCurrentDevice") ?? true
        )
    }

    /// A property of a CallKit object, if it has one by that getter: reading one it lacks throws.
    private static func value(_ object: NSObject, _ getter: String) -> Any? {
        object.responds(to: NSSelectorFromString(getter)) ? object.value(forKey: getter) : nil
    }
}
