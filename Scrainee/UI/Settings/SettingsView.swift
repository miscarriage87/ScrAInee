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
                Toggle("Aufnahme automatisch starten", isOn: $autoStartCapture)
                    .help("Startet die Bildschirmaufnahme automatisch beim Öffnen der App")
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

            Text(title)

            Spacer()

            if !granted {
                Button("Berechtigen") {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
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

                VStack(alignment: .leading) {
                    Text("Bildqualitaet: \(Int(heicQuality * 100))%")
                    Slider(value: $heicQuality, in: 0.3...1.0, step: 0.1)
                }

                Toggle("OCR aktivieren", isOn: $ocrEnabled)
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
                    } else {
                        Button("Herunterladen") {
                            downloadModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading)
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

                Toggle("Live Meeting-Minutes", isOn: $liveMinutesEnabled)
                    .disabled(!whisperModelDownloaded)
                    .help("Generiert Meeting-Zusammenfassungen waehrend des Meetings")
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
                }

                // Action buttons
                HStack {
                    Button("Speichern") {
                        saveAPIKey()
                    }
                    .disabled(claudeAPIKey.isEmpty || isSaving)

                    Button("Testen") {
                        Task { await testAPIKey() }
                    }
                    .disabled(claudeAPIKey.isEmpty || isTesting)
                    .buttonStyle(.borderedProminent)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button("Loeschen") {
                        deleteAPIKey()
                    }
                    .foregroundColor(.red)
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
                Link("API Dokumentation", destination: URL(string: "https://docs.anthropic.com/")!)
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
            Text(apiKeyStatus.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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

                    Button("Verbindung testen") {
                        Task { await testNotionConnection() }
                    }
                    .disabled(notionAPIKey.isEmpty || notionDatabaseId.isEmpty || notionTestStatus == .testing)

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
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(notionStatusMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .error:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(notionStatusMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
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

                Button("Jetzt aufraeumen") {
                    Task {
                        await RetentionPolicy.shared.performCleanup()
                        await refreshStats()
                    }
                }
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
