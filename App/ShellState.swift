import DeskpouchCore
import Foundation
import Observation
import ToolScreenRecorder

/// What the menubar panel shows. Written by `Shell`, read by SwiftUI. Pure UI state (which view, which card is
/// expanded) is written by the views themselves.
@MainActor
@Observable
final class ShellState {
    enum PanelView: Equatable {
        case main
        case general
        /// One tool's own view: its card, chips and options.
        case tool(String)
        /// Everything logged, with search, filter and paging.
        case history
    }

    enum HistoryFilter: String, CaseIterable {
        case all, voice, recordings

        var label: String {
            switch self {
            case .all: "All"
            case .voice: "Voice"
            case .recordings: "Recordings"
            }
        }

        var toolID: String? {
            switch self {
            case .all: nil
            case .voice: "voice"
            case .recordings: "screen"
            }
        }
    }

    var isListening = false
    /// The hold key monitors are live.
    var hotkeyReady = false
    var holdKey: ModifierKey = .rightOption
    /// Engine line in the voice card, e.g. "Parakeet v3 · local".
    var voiceStatus = "Parakeet v3"
    /// What the recorder is doing; drives the menubar timer and the screen card.
    var activity: ToolActivity = .idle
    var screenKey: KeyCombo = .commandShift6
    /// Settings line in the screen card, e.g. "1080p · system audio".
    var screenStatus = "1080p · 60 fps · system audio"
    /// The recorder's key combo could not be registered (another app owns it).
    var screenKeyTaken = false
    /// 20 bar meter in the voice card, fed from the overlay's ticks.
    let panelMeter = LevelMeterModel(barCount: 20)
    /// Per-tool after-capture actions. The chips row reads and writes through `Shell`.
    let output: OutputSettings
    /// Last few history items, newest first, the total count, and the size of the files they point at.
    var recent: [HistoryItem] = []
    var historyCount = 0
    var historyBytes: Int64 = 0
    /// Frames for the file tiles under Recent.
    let thumbnails = ThumbnailCache()
    /// The panel is on screen; drives its spring-in.
    var panelPresented = false
    var version = "0.1.0"

    // Navigation, written by the views.
    var panelView: PanelView = .main
    let popups = PopupController()
    /// Height the panel content may use before the History list has to scroll.
    var panelMaxHeight: CGFloat = 800

    // History view.
    var historyQuery = ""
    var historyFilter: HistoryFilter = .all
    /// Rows loaded so far for the current query and filter, newest first, and how many match in total.
    var historyItems: [HistoryItem] = []
    var historyMatches = 0
    /// "Clear…" was clicked; the row shows the confirmation.
    var confirmingClear = false

    // Voice options.
    struct EngineOption: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
    }
    var voiceEngine = "Parakeet v3"
    var voiceEngineID = "parakeet"
    var voiceEngines: [EngineOption] = []
    var voiceModelStatus = ""
    var parakeetDownloaded = false
    var voiceLanguage = "en"
    var voiceLanguages: [String] = []
    var voiceMicrophoneUID: String?
    var voiceSkipFillers = true
    var microphones: [AudioInputDevice] = []

    // Screen options.
    var recorderSettings = RecorderSettings()
    /// nil means the pipeline's default folder.
    var screenFolder: URL?

    // General.
    let general: GeneralSettings
    var permissions = PermissionStatus()

    init(output: OutputSettings = OutputSettings(), general: GeneralSettings = GeneralSettings()) {
        self.output = output
        self.general = general
    }
}
