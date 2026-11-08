import AppKit
import SwiftUI

/// First-launch consent for processing and storing health data. Nothing reads CareLink until
/// the current consent version is accepted. Bump `version` when the text changes materially.
enum Consent {
    static let version = 1
    private static let versionKey = "consentVersion"
    private static let dateKey = "consentDate"

    static var isAccepted: Bool { UserDefaults.standard.integer(forKey: versionKey) >= version }
    static var acceptedAt: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    static func accept(now: Date = Date()) {
        UserDefaults.standard.set(version, forKey: versionKey)
        UserDefaults.standard.set(now, forKey: dateKey)
    }
    static func reset() {
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }

    /// Paragraphs shown in the consent window (Portuguese keys, translated by tr()).
    static let paragraphs = ["consent.read", "consent.store", "consent.sharing", "consent.responsibility", "consent.unofficial"]
}

struct ConsentView: View {
    @ObservedObject var prefs: Preferences
    var onAccept: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Antes de começar")).font(.title2.weight(.semibold))
                    Text(tr("Consentimento para utilizar o CareLink Menubar")).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $prefs.language) {
                    Text("Português").tag(AppLanguage.portuguese)
                    Text("English").tag(AppLanguage.english)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            // Rows are keyed by the translated text (and the block by language) so switching the
            // language redraws them; keying by the constant keys left the old language on screen.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Consent.paragraphs.map { tr($0) }, id: \.self) { paragraph in
                    Text(paragraph).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .id(prefs.language)
            HStack {
                Button(tr("Sair")) { onQuit() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("Aceito e quero continuar")) { onAccept() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, L10n.locale)
    }
}
