import AppKit
import EventKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = EKEventStore()
    private let flasher = Flasher()
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var hasAccess = false
    private var settingsWindow: NSWindow?
    /// Alerts already fired, keyed by event id + start time + alert id (recurring events share an id).
    private var fired: [String: Date] = [:]

    private let settings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A long custom sound shouldn't keep playing once you've acknowledged the flash.
        flasher.onDismiss = { Sounds.stop() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "MeetingFlash")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.hasAccess = granted
                self?.tick()
            }
        }

        // Polling every few seconds is simple and survives sleep, clock changes and calendar edits.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    // MARK: - Calendar

    private func relevantEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let calendars = store.calendars(for: .event).filter { !settings.disabledCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { event in
                if event.isAllDay || event.status == .canceled { return false }
                if settings.ignoreFree && event.availability == .free { return false }
                let me = event.attendees?.first(where: \.isCurrentUser)
                if me?.participantStatus == .declined { return false }
                return true
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func key(_ e: EKEvent) -> String {
        "\(e.eventIdentifier ?? e.calendarItemIdentifier)@\(e.startDate.timeIntervalSince1970)"
    }

    private func tick() {
        let now = Date()
        let events = relevantEvents(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(24 * 3600))
        settings.remember(AudioOutputs.all())
        if let ssid = WiFi.shared.currentSSID { settings.remember(networks: [ssid]) }

        for event in events {
            // Only meetings that haven't been running for more than a minute.
            guard now < event.startDate.addingTimeInterval(60) else { continue }
            let due = settings.alerts.filter { now >= event.startDate.addingTimeInterval(-TimeInterval($0.minutesBefore * 60)) }
            // If several are due (e.g. after wake), fire only the latest and mark the older ones as done.
            guard let latest = due.min(by: { $0.minutesBefore < $1.minutesBefore }),
                  fired[key(event) + latest.id.uuidString] == nil else { continue }
            due.forEach { fired[key(event) + $0.id.uuidString] = now }
            fire(latest, title: event.title ?? "Meeting", subtitle: Self.startsText(event.startDate, now: now))
            break
        }
        fired = fired.filter { now.timeIntervalSince($0.value) < 24 * 3600 }

        updateStatusTitle(events: events, now: now)
    }

    private func fire(_ alert: MeetingAlert, title: String, subtitle: String) {
        if alert.flash { flasher.flash(title: title, subtitle: subtitle, look: settings.flashLook) }
        if let sound = alert.sound, settings.soundAllowedNow { Sounds.play(sound) }
    }

    private func updateStatusTitle(events: [EKEvent], now: Date) {
        guard let button = statusItem.button else { return }
        if !hasAccess {
            button.title = " !"
            return
        }
        // Show a countdown once the next meeting is within the hour.
        if let next = events.first(where: { $0.startDate > now }), next.startDate.timeIntervalSince(now) < 3600 {
            let mins = Int(ceil(next.startDate.timeIntervalSince(now) / 60))
            button.title = " \(mins)m"
        } else {
            button.title = ""
        }
    }

    private static func startsText(_ start: Date, now: Date) -> String {
        let secs = start.timeIntervalSince(now)
        if secs <= 30 { return "Starting now" }
        let mins = Int(ceil(secs / 60))
        return "Starts in \(mins) minute\(mins == 1 ? "" : "s")"
    }

    private static let meetingLinkRegex = try! NSRegularExpression(
        pattern: #"https://[^\s<>"]*(teams\.microsoft\.com|teams\.live\.com|zoom\.us|meet\.google\.com|webex\.com)[^\s<>"]*"#)

    private static func joinURL(for event: EKEvent) -> URL? {
        let haystacks = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in haystacks {
            let range = NSRange(text.startIndex..., in: text)
            if let m = meetingLinkRegex.firstMatch(in: text, range: range), let r = Range(m.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !hasAccess {
            menu.addItem(item("Grant Calendar Access…", #selector(openPrivacySettings)))
            menu.addItem(.separator())
        } else {
            let now = Date()
            let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(36 * 3600)
            let upcoming = relevantEvents(from: now.addingTimeInterval(-3600), to: endOfDay)
                .filter { $0.endDate > now }
                .prefix(8)
            menu.addItem(header(upcoming.isEmpty ? "No upcoming meetings" : "Upcoming"))
            let fmt = DateFormatter()
            fmt.dateStyle = .none
            fmt.timeStyle = .short
            for event in upcoming {
                var label = "\(fmt.string(from: event.startDate))  \(event.title ?? "Meeting")"
                if !Calendar.current.isDateInToday(event.startDate) { label = "Tomorrow " + label }
                if let url = Self.joinURL(for: event) {
                    let mi = item(label + "  ↗", #selector(openJoinURL(_:)))
                    mi.representedObject = url
                    mi.toolTip = "Join: \(url.absoluteString)"
                    menu.addItem(mi)
                } else {
                    let mi = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                    mi.isEnabled = false
                    menu.addItem(mi)
                }
            }
            menu.addItem(.separator())
        }

        // Calendars
        if hasAccess {
            let calItem = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
            let calMenu = NSMenu()
            let bySource = Dictionary(grouping: store.calendars(for: .event), by: { $0.source.title })
            for source in bySource.keys.sorted() {
                calMenu.addItem(header(source))
                for cal in bySource[source]!.sorted(by: { $0.title < $1.title }) {
                    let mi = item(cal.title, #selector(toggleCalendar(_:)))
                    mi.representedObject = cal.calendarIdentifier
                    mi.state = settings.disabledCalendarIDs.contains(cal.calendarIdentifier) ? .off : .on
                    mi.image = Self.swatch(cal.color)
                    calMenu.addItem(mi)
                }
            }
            calItem.submenu = calMenu
            menu.addItem(calItem)
        }

        let freeItem = item("Ignore Events Marked “Free”", #selector(toggleIgnoreFree))
        freeItem.state = settings.ignoreFree ? .on : .off
        menu.addItem(freeItem)

        let loginItem = item("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Test Alert", #selector(testFlash), key: "t"))
        menu.addItem(item("Quit MeetingFlash", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return mi
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    // MARK: - Actions

    @objc private func toggleCalendar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if settings.disabledCalendarIDs.contains(id) {
            settings.disabledCalendarIDs.remove(id)
        } else {
            settings.disabledCalendarIDs.insert(id)
        }
        tick()
    }

    @objc private func toggleIgnoreFree() { settings.ignoreFree.toggle(); tick() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nTip: move MeetingFlash.app into /Applications first."
            alert.runModal()
        }
    }

    /// Fires the alert closest to the meeting start, exactly as a real one would (sound rules included).
    @objc private func testFlash() {
        let next = relevantEvents(from: Date(), to: Date().addingTimeInterval(24 * 3600)).first
        let alert = settings.alerts.min(by: { $0.minutesBefore < $1.minutesBefore }) ?? MeetingAlert(minutesBefore: 1)
        fire(alert, title: next?.title ?? "Test Meeting",
             subtitle: next.map { Self.startsText($0.startDate, now: Date()) } ?? "Starts in 1 minute")
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings) { [weak self] in
                guard let self else { return }
                flasher.flash(title: "Test Meeting", subtitle: "Starts in 1 minute", look: settings.flashLook)
            }))
            window.title = "MeetingFlash Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openJoinURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
