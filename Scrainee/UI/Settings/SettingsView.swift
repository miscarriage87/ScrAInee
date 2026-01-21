// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: SettingsView.swift | PURPOSE: App Settings (Tabbed Interface) | LAYER: UI/Settings
//
// DEPENDENCIES:
//   - AppState (App/AppState.swift) - Global app state via @EnvironmentObject
//   - KeychainAccess (External) - Secure credential storage for API keys
//   - PermissionManager (Services/PermissionManager.swift) - Permission checks & requests
//   - WhisperTranscriptionService (Core/Audio/WhisperTranscriptionService.swift) - Whisper model management
//   - ClaudeAPIClient (Core/AI/ClaudeAPIClient.swift) - API key validation
//   - NotionClient (Core/Integration/NotionClient.swift) - Notion connection test
//   - StorageManager (Core/Storage/StorageManager.swift) - Storage stats
//   - RetentionPolicy (Core/Storage/RetentionPolicy.swift) - Cleanup operations
//   - DatabaseManager (Core/Database/DatabaseManager.swift) - Screenshot count
//   - SettingsValidator (Services/SettingsValidator.swift) - Input validation
//
// DEPENDENTS:
//   - ScraineeApp.swift - Settings scene registration
//   - MenuBarView.swift - Opens via SettingsLink (macOS 14+)
//
// CHANGE IMPACT:
//   - Contains 6 embedded tab views: General, Capture, Transcription, AI, Integration, Storage
//   - API keys stored in Keychain - key names must match KeychainService constants
//   - AppStorage keys affect app behavior globally
//
// LAST UPDATED: 2026-01-21
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import KeychainAccess

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Allgemein", systemImage: "gear")
                }

            CaptureSettingsView()
                .tabItem {
                    Label("Aufnahme", systemImage: "camera")
                }

            TranscriptionSettingsView()
                .tabItem {
                    Label("Transkription", systemImage: "waveform")
                }

            AISettingsView()
                .tabItem {
                    Label("KI", systemImage: "brain")
                }

            IntegrationSettingsView()
                .tabItem {
                    Label("Integrationen", systemImage: "link")
                }

            StorageSettingsView()
                .tabItem {
                    Label("Speicher", systemImage: "internaldrive")
                }
        }
        .frame(width: 550, height: 550)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("autoStartCapture") private var autoStartCapture = true

    var body: some View {
        Form {
            Section {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .accessibilityLabel("Beim Anmelden starten")
                    .accessibilityHint("Scrainee automatisch starten wenn du dich anmeldest")

                Toggle("Aufnahme automatisch starten", isOn: $autoStartCapture)
                    .help("Startet die Bildschirmaufnahme automatisch beim Öffnen der App")
                    .accessibilityLabel("Aufnahme automatisch starten")
                    .accessibilityHint("Screenshot-Aufnahme beim App-Start automatisch beginnen")
            } header: {
                Text("Start")
            }

            Section {
                PermissionStatusView()
            } header: {
                Text("Berechtigungen")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permission Status View

struct PermissionStatusView: View {
    @State private var screenCaptureGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(
                title: "Bildschirmaufnahme",
                granted: screenCaptureGranted,
                action: { PermissionManager.shared.openScreenCapturePreferences() }
            )

            PermissionRow(
                title: "Bedienungshilfen",
                granted: accessibilityGranted,
                action: { PermissionManager.shared.requestAccessibilityPermission() }
            )
        }
        .task {
            await checkPermissions()
        }
    }

    private func checkPermissions() async {
        screenCaptureGranted = await PermissionManager.shared.checkScreenCapturePermission()
        accessibilityGranted = PermissionManager.shared.checkAccessibilityPermission()
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
                .accessibilityHidden(true)

            Text(title)

            Spacer()

            if !granted {
                Button("Berechtigen") {
                    action()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(title) berechtigen")
                .accessibilityHint("Öffnet die Systemeinstellungen für \(title)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(granted ? "Erteilt" : "Nicht erteilt")")
        .accessibilityHint(granted ? "" : "Doppeltippen um Berechtigung zu erteilen")
    }
}

// MARK: - Capture Settings

struct CaptureSettingsView: View {
    @AppStorage("captureInterval") private var captureInterval = 3
    @AppStorage("heicQuality") private var heicQuality = 0.6
    @AppStorage("ocrEnabled") private var ocrEnabled = true

    var body: some View {
        Form {
            Section {
                Picker("Aufnahme-Intervall", selection: $captureInterval) {
                    Text("1 Sekunde").tag(1)
                    Text("2 Sekunden").tag(2)
                    Text("3 Sekunden (Standard)").tag(3)
                    Text("5 Sekunden").tag(5)
                    Text("10 Sekunden").tag(10)
                }
                .accessibilityLabel("Aufnahme-Intervall")
                .accessibilityHint("Wie oft ein Screenshot erstellt wird")

                VStack(alignment: .leading) {
                    Text("Bildqualitaet: \(Int(heicQuality * 100))%")
                    Slider(value: $heicQuality, in: 0.3...1.0, step: 0.1)
                        .accessibilityLabel("Bildqualität")
                        .accessibilityValue("\(Int(heicQuality * 100)) Prozent")
                        .accessibilityHint("Höhere Qualität bedeutet mehr Speicherverbrauch")
                }

                Toggle("OCR aktivieren", isOn: $ocrEnabled)
                    .accessibilityLabel("OCR Texterkennung aktivieren")
                    .accessibilityHint("Extrahiert Text aus Screenshots für die Suche")
            } header: {
                Text("Screenshot-Einstellungen")
            } footer: {
                Text("Hoehere Qualitaet = mehr Speicherverbrauch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettingsView: View {
    @AppStorage("autoTranscribe") private var autoTranscribe = true
    @AppStorage("liveMinutesEnabled") private var liveMinutesEnabled = true
    @AppStorage("whisperModelDownloaded") private var whisperModelDownloaded = false

    // Local state for whisper service (since it's not ObservableObject)
    @State private var isModelLoaded = false
    @State private var isDownloading = false
    @State private var loadingStatus = ""
    @State private var downloadProgress: Double = 0
    @State private var whisperError: String?

    private let whisperService = WhisperTranscriptionService.shared

    var body: some View {
        Form {
            Section {
                // Model status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Whisper Modell (Large)")
                            .font(.headline)
                        Text(whisperService.modelSizeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isModelLoaded {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Geladen")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else if whisperModelDownloaded {
                        Button("Laden") {
                            loadModel()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDownloading)
                        .accessibilityLabel("Whisper Modell laden")
                        .accessibilityHint("Lädt das heruntergeladene Spracherkennungsmodell in den Speicher")
                    } else {
                        Button("Herunterladen") {
                            downloadModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading)
                        .accessibilityLabel("Whisper Modell herunterladen")
                        .accessibilityHint("Lädt das 3 GB große Spracherkennungsmodell herunter")
                    }
                }

                // Download progress
                if !loadingStatus.isEmpty {
                    HStack {
                        if downloadProgress > 0 && downloadProgress < 1 {
                            ProgressView(value: downloadProgress)
                                .progressViewStyle(.linear)
                        }
                        Text(loadingStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Error message
                if let error = whisperError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Whisper Spracherkennung")
            } footer: {
                Text("Lokale Spracherkennung mit OpenAI Whisper. Erfordert einmaligen Download.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Automatisch bei Meetings starten", isOn: $autoTranscribe)
                    .disabled(!whisperModelDownloaded)
                    .help("Startet die Transkription automatisch wenn ein Meeting erkannt wird")
                    .accessibilityLabel("Automatisch bei Meetings starten")
                    .accessibilityHint(whisperModelDownloaded ? "Transkription startet automatisch bei erkannten Meetings" : "Whisper Modell muss erst heruntergeladen werden")

                Toggle("Live Meeting-Minutes", isOn: $liveMinutesEnabled)
                    .disabled(!whisperModelDownloaded)
                    .help("Generiert Meeting-Zusammenfassungen waehrend des Meetings")
                    .accessibilityLabel("Live Meeting-Minutes")
                    .accessibilityHint(whisperModelDownloaded ? "Erstellt Zusammenfassungen während des Meetings" : "Whisper Modell muss erst heruntergeladen werden")
            } header: {
                Text("Automatisierung")
            }

            Section {
                HStack {
                    Text("Unterstuetzte Sprachen")
                    Spacer()
                    Text("Deutsch, Englisch, 95+ weitere")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Modell-Qualitaet")
                    Spacer()
                    Text("Beste (Large-v3)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Verarbeitung")
                    Spacer()
                    Text("Lokal (keine Cloud)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Information")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            updateState()
        }
    }

    // MARK: - Actions

    private func downloadModel() {
        isDownloading = true
        loadingStatus = "Starte Download..."
        whisperError = nil

        Task {
            do {
                try await whisperService.downloadModel()
                await MainActor.run {
                    updateState()
                    whisperModelDownloaded = whisperService.isModelDownloaded
                }
            } catch {
                await MainActor.run {
                    whisperError = error.localizedDescription
                    isDownloading = false
                    loadingStatus = ""
                }
            }
        }
    }

    private func loadModel() {
        isDownloading = true
        loadingStatus = "Lade Modell..."
        whisperError = nil

        Task {
            do {
                try await whisperService.loadModel()
                await MainActor.run {
                    updateState()
                }
            } catch {
                await MainActor.run {
                    whisperError = error.localizedDescription
                    isDownloading = false
                    loadingStatus = ""
                }
            }
        }
    }

    private func updateState() {
        isModelLoaded = whisperService.isModelLoaded
        isDownloading = whisperService.isTranscribing
        loadingStatus = whisperService.loadingStatus
        downloadProgress = whisperService.downloadProgress
        whisperError = whisperService.error
        whisperModelDownloaded = whisperService.isModelDownloaded
    }
}

// MARK: - AI Settings

struct AISettingsView: View {
    @State private var claudeAPIKey = ""
    @State private var isAPIKeyVisible = false
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var apiKeyStatus: APIKeyStatus = .unknown

    private let keychain = Keychain(service: "com.cpohl.scrainee")

    var body: some View {
        Form {
            Section {
                // API Key Input with status indicator
                HStack {
                    // Status indicator
                    apiKeyStatusIcon

                    if isAPIKeyVisible {
                        if #available(macOS 14.0, *) {
                            TextField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: claudeAPIKey) { _, _ in
                                    validateKeyFormat()
                                }
                        } else {
                            // Fallback on earlier versions
                        }
                    } else {
                        if #available(macOS 14.0, *) {
                            SecureField("sk-ant-...", text: $claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: claudeAPIKey) { _, _ in
                                    validateKeyFormat()
                                }
                        } else {
                            // Fallback on earlier versions
                        }
                    }

                    Button(action: { isAPIKeyVisible.toggle() }) {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isAPIKeyVisible ? "API Key verbergen" : "API Key anzeigen")
                    .accessibilityHint("Schaltet die Sichtbarkeit des API Keys um")
                }

                // Action buttons
                HStack {
                    Button("Speichern") {
                        saveAPIKey()
                    }
                    .disabled(claudeAPIKey.isEmpty || isSaving)
                    .accessibilityLabel("API Key speichern")
                    .accessibilityHint("Speichert den API Key sicher im Schlüsselbund")

                    Button("Testen") {
                        Task { await testAPIKey() }
                    }
                    .disabled(claudeAPIKey.isEmpty || isTesting)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("API Key testen")
                    .accessibilityHint("Prüft ob der API Key gültig ist")

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .accessibilityLabel("Teste API Verbindung")
                    }

                    Button("Loeschen") {
                        deleteAPIKey()
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("API Key löschen")
                    .accessibilityHint("Entfernt den gespeicherten API Key")
                }

                // Status message
                if let message = statusMessage {
                    HStack {
                        Image(systemName: apiKeyStatus.icon)
                            .foregroundColor(apiKeyStatus.color)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(apiKeyStatus.color)
                    }
                }
            } header: {
                HStack {
                    Text("Claude API Key")
                    Spacer()
                    apiKeyStatusBadge
                }
            } footer: {
                Text("Hol dir deinen API Key von console.anthropic.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Link("Anthropic Console", destination: URL(string: "https://console.anthropic.com/")!)
                    .accessibilityLabel("Anthropic Console öffnen")
                    .accessibilityHint("Öffnet die Anthropic Console im Browser")

                Link("API Dokumentation", destination: URL(string: "https://docs.anthropic.com/")!)
                    .accessibilityLabel("API Dokumentation öffnen")
                    .accessibilityHint("Öffnet die Claude API Dokumentation im Browser")
            } header: {
                Text("Links")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadAPIKey()
        }
    }

    // MARK: - Status Views

    @ViewBuilder
    private var apiKeyStatusIcon: some View {
        Image(systemName: apiKeyStatus.icon)
            .foregroundColor(apiKeyStatus.color)
            .font(.title3)
    }

    @ViewBuilder
    private var apiKeyStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(apiKeyStatus.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(apiKeyStatus.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("API Key Status: \(apiKeyStatus.label)")
    }

    // MARK: - API Key Management

    private func loadAPIKey() {
        claudeAPIKey = (try? keychain.get("claude_api_key")) ?? ""
        if !claudeAPIKey.isEmpty {
            validateKeyFormat()
        }
    }

    private func validateKeyFormat() {
        if claudeAPIKey.isEmpty {
            apiKeyStatus = .unknown
        } else if !claudeAPIKey.hasPrefix("sk-ant-") {
            apiKeyStatus = .invalidFormat
            statusMessage = "API Key muss mit 'sk-ant-' beginnen"
        } else if claudeAPIKey.count < 20 {
            apiKeyStatus = .invalidFormat
            statusMessage = "API Key ist zu kurz"
        } else {
            apiKeyStatus = .formatValid
            statusMessage = nil
        }
    }

    private func saveAPIKey() {
        isSaving = true
        do {
            try keychain.set(claudeAPIKey, key: "claude_api_key")
            statusMessage = "Gespeichert"
            apiKeyStatus = .saved
        } catch {
            statusMessage = "Fehler: \(error.localizedDescription)"
            apiKeyStatus = .error
        }
        isSaving = false

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if apiKeyStatus == .saved {
                validateKeyFormat()
            }
        }
    }

    private func testAPIKey() async {
        isTesting = true
        apiKeyStatus = .testing
        statusMessage = "Teste Verbindung..."

        do {
            let client = ClaudeAPIClient()
            try await client.testConnection()
            apiKeyStatus = .valid
            statusMessage = "API Key ist gueltig und aktiv!"
        } catch let error as ClaudeAPIError {
            apiKeyStatus = .invalid
            switch error {
            case .invalidAPIKey:
                statusMessage = "Ungueltiger API Key"
            case .rateLimited:
                statusMessage = "Rate Limit erreicht - Key ist aber gueltig"
                apiKeyStatus = .valid
            case .serverError(let message):
                statusMessage = "Server-Fehler: \(message)"
            default:
                statusMessage = "Fehler: \(error.localizedDescription)"
            }
        } catch {
            apiKeyStatus = .error
            statusMessage = "Verbindungsfehler: \(error.localizedDescription)"
        }

        isTesting = false
    }

    private func deleteAPIKey() {
        try? keychain.remove("claude_api_key")
        claudeAPIKey = ""
        apiKeyStatus = .unknown
        statusMessage = "API Key geloescht"

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            statusMessage = nil
        }
    }
}

// MARK: - API Key Status

enum APIKeyStatus {
    case unknown
    case invalidFormat
    case formatValid
    case testing
    case valid
    case invalid
    case saved
    case error

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .invalidFormat: return "exclamationmark.triangle.fill"
        case .formatValid: return "checkmark.circle"
        case .testing: return "arrow.triangle.2.circlepath"
        case .valid: return "checkmark.seal.fill"
        case .invalid: return "xmark.seal.fill"
        case .saved: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .invalidFormat: return .orange
        case .formatValid: return .blue
        case .testing: return .blue
        case .valid: return .green
        case .invalid: return .red
        case .saved: return .green
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .unknown: return "Nicht konfiguriert"
        case .invalidFormat: return "Ungueltiges Format"
        case .formatValid: return "Format OK"
        case .testing: return "Teste..."
        case .valid: return "Aktiv"
        case .invalid: return "Ungueltig"
        case .saved: return "Gespeichert"
        case .error: return "Fehler"
        }
    }
}

// MARK: - Integration Settings

struct IntegrationSettingsView: View {
    @AppStorage("meetingDetectionEnabled") private var meetingDetectionEnabled = true
    @State private var notionAPIKey = ""
    @State private var notionDatabaseId = ""
    @State private var notionTestStatus: NotionTestStatus = .idle
    @State private var notionStatusMessage = ""
    @State private var validationError = ""

    private let keychain = Keychain(service: "com.cpohl.scrainee")

    enum NotionTestStatus {
        case idle, testing, success, error
    }

    var body: some View {
        Form {
            Section {
                Toggle("Meeting-Erkennung aktivieren", isOn: $meetingDetectionEnabled)
                    .accessibilityLabel("Meeting-Erkennung aktivieren")
                    .accessibilityHint("Erkennt automatisch laufende Meetings in Teams, Zoom, Webex und Google Meet")

                Text("Unterstuetzte Apps: Microsoft Teams, Zoom, Webex, Google Meet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Meeting-Erkennung")
            }

            Section {
                SecureField("Notion API Key", text: $notionAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: notionAPIKey) {
                        validateInputs()
                        notionTestStatus = .idle
                    }

                TextField("Database ID", text: $notionDatabaseId)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: notionDatabaseId) {
                        validateInputs()
                        notionTestStatus = .idle
                    }

                // Validierungsfehler anzeigen
                if !validationError.isEmpty {
                    Text(validationError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Button("Speichern") {
                        saveNotionSettings()
                    }
                    .disabled(!validationError.isEmpty && !notionAPIKey.isEmpty)
                    .accessibilityLabel("Notion Einstellungen speichern")
                    .accessibilityHint("Speichert API Key und Database ID sicher")

                    Button("Verbindung testen") {
                        Task { await testNotionConnection() }
                    }
                    .disabled(notionAPIKey.isEmpty || notionDatabaseId.isEmpty || notionTestStatus == .testing)
                    .accessibilityLabel("Notion Verbindung testen")
                    .accessibilityHint("Prüft ob die Notion Integration funktioniert")

                    Spacer()

                    // Status-Anzeige
                    notionStatusView
                }
            } header: {
                Text("Notion Integration")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Erstelle eine Integration unter notion.so/my-integrations")
                    Text("Die Database ID findest du in der URL deiner Notion-Datenbank")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadNotionSettings()
        }
    }

    @ViewBuilder
    private var notionStatusView: some View {
        switch notionTestStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Teste...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Teste Notion Verbindung")
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .accessibilityHidden(true)
                Text(notionStatusMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Erfolg: \(notionStatusMessage)")
        case .error:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .accessibilityHidden(true)
                Text(notionStatusMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fehler: \(notionStatusMessage)")
        }
    }

    private func loadNotionSettings() {
        notionAPIKey = (try? keychain.get("notion_api_key")) ?? ""
        notionDatabaseId = (try? keychain.get("notion_database_id")) ?? ""
    }

    private func saveNotionSettings() {
        try? keychain.set(notionAPIKey, key: "notion_api_key")
        try? keychain.set(notionDatabaseId, key: "notion_database_id")
        notionStatusMessage = "Gespeichert"
        notionTestStatus = .success

        // Status nach 2 Sekunden zurücksetzen
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notionStatusMessage == "Gespeichert" {
                notionTestStatus = .idle
            }
        }
    }

    private func validateInputs() {
        validationError = ""

        if !notionAPIKey.isEmpty {
            let keyResult = SettingsValidator.validateNotionAPIKey(notionAPIKey)
            if case .invalid(let message) = keyResult {
                validationError = message
                return
            }
        }

        if !notionDatabaseId.isEmpty {
            let dbResult = SettingsValidator.validateNotionDatabaseId(notionDatabaseId)
            if case .invalid(let message) = dbResult {
                validationError = message
                return
            }
        }
    }

    private func testNotionConnection() async {
        notionTestStatus = .testing
        notionStatusMessage = ""

        // Erst speichern, damit der NotionClient die Credentials laden kann
        try? keychain.set(notionAPIKey, key: "notion_api_key")
        try? keychain.set(notionDatabaseId, key: "notion_database_id")

        let client = NotionClient()

        do {
            let success = try await client.testConnection()
            if success {
                notionTestStatus = .success
                notionStatusMessage = "Verbindung erfolgreich!"
            } else {
                notionTestStatus = .error
                notionStatusMessage = "Verbindung fehlgeschlagen"
            }
        } catch {
            notionTestStatus = .error
            notionStatusMessage = error.localizedDescription
        }
    }
}

// MARK: - Storage Settings

struct StorageSettingsView: View {
    @AppStorage("retentionDays") private var retentionDays = 30
    @State private var storageUsed = "Berechne..."
    @State private var screenshotCount = 0

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Speicherverbrauch")
                    Spacer()
                    Text(storageUsed)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Screenshots")
                    Spacer()
                    Text("\(screenshotCount)")
                        .foregroundColor(.secondary)
                }

                Button("Im Finder anzeigen") {
                    // Use activateFileViewerSelecting to ensure Finder opens (not third-party file managers)
                    NSWorkspace.shared.activateFileViewerSelecting([StorageManager.shared.applicationSupportDirectory])
                }
                .accessibilityLabel("Speicherordner im Finder anzeigen")
                .accessibilityHint("Öffnet den Ordner mit allen Scrainee Daten im Finder")
            } header: {
                Text("Speicher")
            }

            Section {
                Picker("Aufbewahrungsdauer", selection: $retentionDays) {
                    Text("7 Tage").tag(7)
                    Text("14 Tage").tag(14)
                    Text("30 Tage (Standard)").tag(30)
                    Text("60 Tage").tag(60)
                    Text("90 Tage").tag(90)
                    Text("Unbegrenzt").tag(0)
                }
                .accessibilityLabel("Aufbewahrungsdauer")
                .accessibilityHint("Wie lange Screenshots aufbewahrt werden bevor sie automatisch gelöscht werden")

                Button("Jetzt aufraeumen") {
                    Task {
                        await RetentionPolicy.shared.performCleanup()
                        await refreshStats()
                    }
                }
                .accessibilityLabel("Jetzt aufräumen")
                .accessibilityHint("Löscht alte Screenshots entsprechend der Aufbewahrungsdauer")
            } header: {
                Text("Aufbewahrung")
            } footer: {
                if retentionDays > 0 {
                    Text("Screenshots aelter als \(retentionDays) Tage werden automatisch geloescht")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button("Alle Screenshots loeschen", role: .destructive) {
                    // Show confirmation dialog
                }
                .accessibilityLabel("Alle Screenshots löschen")
                .accessibilityHint("Achtung: Löscht unwiderruflich alle gespeicherten Screenshots")
            } header: {
                Text("Gefahrenzone")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await refreshStats()
        }
    }

    private func refreshStats() async {
        storageUsed = StorageManager.shared.formattedStorageUsed
        screenshotCount = (try? await DatabaseManager.shared.getScreenshotCount()) ?? 0
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
