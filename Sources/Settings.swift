import AppKit
import CoreAudio

/// One reminder before a meeting: when it fires, whether it flashes, and which sound it plays.
struct MeetingAlert: Codable, Identifiable, Hashable {
    var id = UUID()
    var minutesBefore: Int
    var flash: Bool = true
    var sound: String? = nil
}

enum FlashStyle: String, Codable {
    case color, photo
}

/// An sRGB colour with opacity, stored as plain numbers.
struct RGBA: Codable, Equatable {
    var red, green, blue, alpha: Double

    static let defaultRed = RGBA(red: 1, green: 0.231, blue: 0.188, alpha: 0.55)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .systemRed
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var alerts: [MeetingAlert] { didSet { save(alerts, "alerts") } }
    @Published var flashStyle: FlashStyle { didSet { defaults.set(flashStyle.rawValue, forKey: "flashStyle") } }
    @Published var flashColor: RGBA { didSet { save(flashColor, "flashColor") } }
    /// Our own copy of the chosen photo, so the flash keeps working if the original moves.
    @Published private(set) var flashPhoto: URL? { didSet { defaults.set(flashPhoto?.path, forKey: "flashPhoto") } }
    /// File name of the photo as the user picked it, for display.
    @Published private(set) var flashPhotoName: String? { didSet { defaults.set(flashPhotoName, forKey: "flashPhotoName") } }
    @Published var ignoreFree: Bool { didSet { defaults.set(ignoreFree, forKey: "ignoreFree") } }
    @Published var disabledCalendarIDs: Set<String> { didSet { defaults.set(Array(disabledCalendarIDs), forKey: "disabledCalendars") } }
    /// When on, sounds only play if the current output device is in `allowedOutputUIDs`.
    @Published var restrictOutputs: Bool { didSet { defaults.set(restrictOutputs, forKey: "restrictOutputs") } }
    @Published var allowedOutputUIDs: Set<String> { didSet { defaults.set(Array(allowedOutputUIDs), forKey: "allowedOutputs") } }
    /// Every output device seen so far (UID → name), so AirPods can be picked while disconnected.
    @Published private(set) var knownOutputs: [String: String] { didSet { save(knownOutputs, "knownOutputs") } }
    /// Per allowed output: Wi-Fi networks it may play on. Missing or empty means anywhere.
    @Published var outputNetworks: [String: [String]] { didSet { save(outputNetworks, "outputNetworks") } }
    /// Wi-Fi networks where alerts never make sound, whatever the output.
    @Published var quietNetworks: Set<String> { didSet { defaults.set(Array(quietNetworks), forKey: "quietNetworks") } }
    @Published private(set) var knownNetworks: Set<String> { didSet { defaults.set(Array(knownNetworks), forKey: "knownNetworks") } }

    init() {
        if let alerts: [MeetingAlert] = Self.load("alerts") {
            self.alerts = alerts
        } else {
            // Carry over the 1.0 single lead-time setting.
            self.alerts = [MeetingAlert(minutesBefore: defaults.object(forKey: "leadMinutes") as? Int ?? 1)]
        }
        flashStyle = defaults.string(forKey: "flashStyle").flatMap(FlashStyle.init) ?? .color
        flashColor = Self.load("flashColor") ?? .defaultRed
        flashPhoto = defaults.string(forKey: "flashPhoto").map(URL.init(fileURLWithPath:))
        flashPhotoName = defaults.string(forKey: "flashPhotoName")
        ignoreFree = defaults.object(forKey: "ignoreFree") as? Bool ?? true
        disabledCalendarIDs = Set(defaults.stringArray(forKey: "disabledCalendars") ?? [])
        restrictOutputs = defaults.bool(forKey: "restrictOutputs")
        allowedOutputUIDs = Set(defaults.stringArray(forKey: "allowedOutputs") ?? [])
        knownOutputs = Self.load("knownOutputs") ?? [:]
        outputNetworks = Self.load("outputNetworks") ?? [:]
        quietNetworks = Set(defaults.stringArray(forKey: "quietNetworks") ?? [])
        knownNetworks = Set(defaults.stringArray(forKey: "knownNetworks") ?? [])
    }

    /// What the flash shows right now. Falls back to the colour if the photo is missing or unreadable.
    var flashLook: FlashLook {
        if flashStyle == .photo, let flashPhoto, let image = NSImage(contentsOf: flashPhoto) {
            return .photo(image)
        }
        return .color(flashColor.nsColor)
    }

    /// Copies the picked image into Application Support and uses it for the flash.
    func setFlashPhoto(from source: URL) throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingFlash", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A new name each time, so the old copy can go and nothing caches a stale image.
        let copy = dir.appendingPathComponent("flash-\(UUID().uuidString).\(source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: copy)
        if let old = flashPhoto { try? FileManager.default.removeItem(at: old) }
        flashPhoto = copy
        flashPhotoName = source.lastPathComponent
        flashStyle = .photo
    }

    func remember(networks: [String]) {
        let new = Set(networks).subtracting(knownNetworks)
        if !new.isEmpty { knownNetworks.formUnion(new) }
    }

    /// True when some rule depends on the Wi-Fi name (and so needs Location access).
    var usesNetworkRules: Bool {
        !quietNetworks.isEmpty || (restrictOutputs && outputNetworks.values.contains { !$0.isEmpty })
    }

    func remember(_ outputs: [AudioOutput]) {
        for o in outputs where knownOutputs[o.uid] != o.name {
            knownOutputs[o.uid] = o.name
        }
    }

    /// Whether alert sounds may play right now, given the Wi-Fi network and current output device.
    var soundAllowedNow: Bool {
        let ssid = WiFi.shared.currentSSID
        if let ssid, quietNetworks.contains(ssid) { return false }
        guard restrictOutputs else { return true }
        guard let current = AudioOutputs.current() else { return false }
        // Some devices (USB, docks) get a new UID per port, so fall back to the name.
        guard let match = allowedOutputUIDs.first(where: { $0 == current.uid })
                ?? allowedOutputUIDs.first(where: { knownOutputs[$0] == current.name }) else { return false }
        let networks = outputNetworks[match] ?? []
        return networks.isEmpty || (ssid.map(networks.contains) ?? false)
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

/// System sounds are stored by name ("Sosumi"); the user's own sounds by file name with extension ("Gong.mp3").
@MainActor
enum Sounds {
    static let names: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
        .map { ($0 as NSString).deletingPathExtension }
        .sorted()

    /// Copies of sounds the user added, in Application Support.
    static let customDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MeetingFlash/Sounds", isDirectory: true)

    static var customNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: customDirectory.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Copies an audio file in (replacing one with the same name) and returns the name to store on the alert.
    static func add(_ source: URL) throws -> String {
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        let copy = customDirectory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
        try FileManager.default.copyItem(at: source, to: copy)
        return source.lastPathComponent
    }

    static func displayName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    private static var playing: NSSound?

    static func play(_ name: String) {
        playing?.stop()
        let custom = customDirectory.appendingPathComponent(name)
        playing = FileManager.default.fileExists(atPath: custom.path)
            ? NSSound(contentsOf: custom, byReference: true)
            : NSSound(named: NSSound.Name(name))
        playing?.play()
    }

    static var isPlaying: Bool { playing?.isPlaying ?? false }

    static func stop() {
        playing?.stop()
        playing = nil
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
        return AudioOutput(uid: canonicalID(uid), name: name)
    }

    private static let macAddress = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{2}([-:][0-9A-Fa-f]{2}){5}")

    /// Bluetooth outputs are identified by their hardware address ("bt:340e22c3b28f"), so a device
    /// found in the paired list matches the CoreAudio device once it connects.
    static func canonicalID(_ raw: String) -> String {
        guard let m = macAddress.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range, in: raw) else { return raw }
        return "bt:" + raw[r].filter(\.isHexDigit).lowercased()
    }

    /// Paired Bluetooth audio devices, connected or not. Reads system_profiler, which (unlike
    /// IOBluetooth) doesn't need Bluetooth permission. Takes a second or so, so call off the main thread.
    static func pairedBluetooth() -> [AudioOutput] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (json["SPBluetoothDataType"] as? [[String: Any]])?.first else { return [] }
        let nonAudio: Set<String> = ["Keyboard", "Mouse", "Trackpad", "Pointing Device", "Gamepad", "Joystick",
                                     "Game Controller", "Remote Control", "Digitizer Tablet", "Card Reader", "Combo"]
        var result: [AudioOutput] = []
        for section in ["device_connected", "device_not_connected"] {
            for entry in controller[section] as? [[String: [String: Any]]] ?? [] {
                for (name, info) in entry {
                    // Phones, watches and computers have no minor type; everything else that isn't an input device may play audio.
                    guard let minor = info["device_minorType"] as? String, !nonAudio.contains(minor),
                          let address = info["device_address"] as? String else { continue }
                    let clean = name.replacingOccurrences(of: " - Find My", with: "").trimmingCharacters(in: .whitespaces)
                    result.append(AudioOutput(uid: canonicalID(address), name: clean))
                }
            }
        }
        return result
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
