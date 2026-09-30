import AppKit
import CoreAudio

/// One reminder before a meeting: when it fires, whether it flashes, and which sound it plays.
struct MeetingAlert: Codable, Identifiable, Hashable {
    var id = UUID()
    var minutesBefore: Int
    var flash: Bool = true
    var sound: String? = nil
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var alerts: [MeetingAlert] { didSet { save(alerts, "alerts") } }
    @Published var ignoreFree: Bool { didSet { defaults.set(ignoreFree, forKey: "ignoreFree") } }
    @Published var disabledCalendarIDs: Set<String> { didSet { defaults.set(Array(disabledCalendarIDs), forKey: "disabledCalendars") } }
    /// When on, sounds only play if the current output device is in `allowedOutputUIDs`.
    @Published var restrictOutputs: Bool { didSet { defaults.set(restrictOutputs, forKey: "restrictOutputs") } }
    @Published var allowedOutputUIDs: Set<String> { didSet { defaults.set(Array(allowedOutputUIDs), forKey: "allowedOutputs") } }
    /// Every output device seen so far (UID → name), so AirPods can be picked while disconnected.
    @Published private(set) var knownOutputs: [String: String] { didSet { save(knownOutputs, "knownOutputs") } }

    init() {
        if let alerts: [MeetingAlert] = Self.load("alerts") {
            self.alerts = alerts
        } else {
            // Carry over the 1.0 single lead-time setting.
            self.alerts = [MeetingAlert(minutesBefore: defaults.object(forKey: "leadMinutes") as? Int ?? 1)]
        }
        ignoreFree = defaults.object(forKey: "ignoreFree") as? Bool ?? true
        disabledCalendarIDs = Set(defaults.stringArray(forKey: "disabledCalendars") ?? [])
        restrictOutputs = defaults.bool(forKey: "restrictOutputs")
        allowedOutputUIDs = Set(defaults.stringArray(forKey: "allowedOutputs") ?? [])
        knownOutputs = Self.load("knownOutputs") ?? [:]
    }

    func remember(_ outputs: [AudioOutput]) {
        for o in outputs where knownOutputs[o.uid] != o.name {
            knownOutputs[o.uid] = o.name
        }
    }

    /// Whether alert sounds may play right now, given the current output device.
    var soundAllowedOnCurrentOutput: Bool {
        guard restrictOutputs else { return true }
        guard let current = AudioOutputs.current() else { return false }
        if allowedOutputUIDs.contains(current.uid) { return true }
        // Some devices (USB, docks) get a new UID per port, so fall back to the name.
        return allowedOutputUIDs.contains { knownOutputs[$0] == current.name }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Sounds

@MainActor
enum Sounds {
    static let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
        .map { ($0 as NSString).deletingPathExtension }
        .sorted()

    private static var playing: NSSound?

    static func play(_ name: String) {
        playing?.stop()
        playing = NSSound(named: NSSound.Name(name))
        playing?.play()
    }
}

// MARK: - Audio outputs

struct AudioOutput: Hashable, Identifiable {
    let uid: String
    let name: String
    var id: String { uid }
}

enum AudioOutputs {
    static func all() -> [AudioOutput] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutput).compactMap(output)
    }

    static func current() -> AudioOutput? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return output(id)
    }

    private static func output(_ id: AudioObjectID) -> AudioOutput? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
        return AudioOutput(uid: uid, name: name)
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
