// Renders the README screenshots (panel light/dark and the three widget sizes) from SYNTHETIC
// example data: an invented 24 h trace with meals and corrections, not anyone's real readings.
// Run through tools/make-screenshots.sh, which compiles it with the app sources.
import AppKit
import SwiftUI
import WidgetKit

@MainActor func save(_ view: some View, _ path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let rep = NSBitmapImageRep(data: renderer.nsImage!.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Synthetic glucose in mg/dL: gentle baseline, three meal excursions, rising now.
func value(hoursAgo h: Double) -> Double {
    func bump(_ at: Double, _ height: Double, _ width: Double) -> Double { height * exp(-pow((h - at) / width, 2)) }
    return 108 + 8 * sin(h / 2.7) + bump(-0.45, 58, 0.95) + bump(6, 72, 1.2) + bump(12.5, 88, 1.5)
        + bump(18.5, 66, 1.3) + 4 * sin(h * 2.1)
}

@main struct MakeScreenshots {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/screenshots"
        let now = Date(), iso = ISO8601DateFormatter(), hour = 3600.0
        let points = (0..<288).map { i -> (Date, Double) in
            let h = Double(287 - i) / 12
            return (now.addingTimeInterval(-180 - h * hour), value(hoursAgo: h + 0.05).rounded())
        }
        let current = points.last!.1
        let prefs = Preferences(defaults: UserDefaults(suiteName: "screenshots.\(UUID().uuidString)")!)
        prefs.language = .english
        let store = CareLinkStore(vault: CredentialVault(service: "screenshots.\(UUID().uuidString)"))
        var snapshot = Snapshot(glucose: current, unit: "mg/dL", timestamp: iso.string(from: points.last!.0), trend: "UP",
                                activeInsulin: 1.35, history: points.map { Reading(timestamp: iso.string(from: $0.0), glucose: $0.1) },
                                synthetic: true)
        snapshot.timeInRange = TimeInRange(inRange: 84, below: 2, above: 14)
        snapshot.reservoirUnits = 142.6; snapshot.reservoirPercent = 48; snapshot.pumpBatteryPercent = 76
        snapshot.sensorHoursLeft = 88; snapshot.infusionMinutesLeft = 2950; snapshot.infusionStatusCode = "NORMAL"
        snapshot.smartGuardState = "AUTO_BASAL"
        snapshot.markers = [(TherapyMarker.Kind.meal, 1.1, 35.0), (.bolus, 1.0, 3.2), (.meal, 6.9, 45), (.bolus, 6.8, 4.2),
                            (.autoCorrection, 5.9, 0.6), (.meal, 13.6, 60), (.bolus, 13.5, 5.5), (.autoCorrection, 12.2, 0.8),
                            (.meal, 19.4, 50), (.bolus, 19.3, 4.8)]
            .map { TherapyMarker(kind: $0.0, date: now.addingTimeInterval(-$0.1 * hour), amount: $0.2) }
        store.snapshot = snapshot; store.isSignedIn = true; store.now = now
        store.lastSuccess = now.addingTimeInterval(-60); store.nextRefresh = now.addingTimeInterval(540)

        for (scheme, name) in [(ColorScheme.dark, "panel-dark"), (.light, "panel-light")] {
            save(CareLinkPopover(store: store, prefs: prefs, exporting: true).content
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20).environment(\.colorScheme, scheme), "\(out)/\(name).png")
        }

        let summary = WidgetSummary(glucoseText: String(format: "%.0f", current), unit: "mg/dL", trendSymbol: "↑",
                                    readingDate: points.last!.0, range: current > 180 ? "high" : "in", updated: now,
                                    language: "en", points: points.suffix(36).map { WidgetPoint(date: $0.0, value: $0.1) },
                                    targetLow: 70, targetHigh: 180, timeInRange: 84, timeBelow: 2, timeAbove: 14,
                                    activeInsulin: 1.35, reservoirUnits: 142.6, pumpBatteryPercent: 76,
                                    infusionMinutesLeft: 2950, infusionChange: false, sensorHoursLeft: 88)
        for (layout, size, name) in [(WidgetLayout.small, CGSize(width: 170, height: 170), "widget-small"),
                                     (.medium, CGSize(width: 364, height: 170), "widget-medium"),
                                     (.large, CGSize(width: 364, height: 382), "widget-large")] {
            let content = SummaryContent(entry: SummaryEntry(date: now, summary: summary), layout: layout)
            // containerBackground only renders inside WidgetKit, so compose the background chart here.
            save(ZStack {
                Color(white: 0.13)
                if layout != .large { content.backgroundChart }
                content.padding(16)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(14).environment(\.colorScheme, .dark), "\(out)/\(name).png")
        }
        print("wrote screenshots to \(out)")
    }
}
