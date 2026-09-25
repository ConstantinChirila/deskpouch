import DeskpouchCore
import SwiftUI
import ToolCalendar

/// The Calendar row in the Tools list: "Next: Design sync · 14:30", amber in the last 5 minutes, mint while an
/// event runs.
struct CalendarRow: View {
    let state: ShellState

    var body: some View {
        let status = rowStatus
        ToolRow(
            name: "Calendar",
            live: status.tint == .soon ? .listening : (status.tint == .live ? .ok : .none),
            open: { state.panelView = .tool(CalendarToolView.toolID) }
        ) {
            CalendarTile()
        } status: {
            Text(status.text).foregroundStyle(status.color)
        } keys: {
            ForEach(Array(state.calendarKey.symbols.enumerated()), id: \.offset) { _, symbol in
                Keycap(symbol)
            }
        }
        .opacity(state.calendarKeyTaken ? 0.7 : 1)
    }

    private var rowStatus: (text: String, tint: Agenda.Tint?, color: Color) {
        guard let model = state.calendar else { return ("", nil, Theme.Colors.textTertiary) }
        switch model.access {
        case .denied: return ("Calendar access is off", nil, Theme.Colors.record)
        case .unknown: return ("Asking for calendar access", nil, Theme.Colors.textTertiary)
        case .granted: break
        }
        let status = model.agenda.rowStatus
        switch status.tint {
        case .soon: return (status.text, .soon, Theme.Colors.accentHigh)
        case .live: return (status.text, .live, Theme.Colors.ok)
        case .plain: return (status.text, .plain, Theme.Colors.textTertiary)
        }
    }
}

/// Mint tile with the calendar page.
struct CalendarTile: View {
    var size: CGFloat = 36

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Theme.Radius.tile * size / 36, style: .continuous)
        CalendarIcon()
            .stroke(style: .icon(1.6))
            .foregroundStyle(Theme.Colors.ok)
            .frame(width: size * 0.45, height: size * 0.45)
            .frame(width: size, height: size)
            .background(tile.fill(LinearGradient(colors: [Theme.Colors.ok(0.22), Theme.Colors.ok(0.08)], startPoint: .top, endPoint: .bottom)))
            .overlay(tile.strokeBorder(Theme.Colors.ok(0.3), lineWidth: 1))
    }
}

/// Calendar (mock "Calendar view A · Agenda list"): today's events with a now line, the next one highlighted
/// with Join, then the options.
struct CalendarToolView: View {
    let state: ShellState
    let actions: MenuPanelActions

    static let toolID = "calendar"

    var body: some View {
        if let model = state.calendar {
            VStack(spacing: 14) {
                switch model.access {
                case .granted:
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        AgendaList(model: model)
                    }
                case .denied:
                    AccessCard(
                        title: "Calendar access is off",
                        detail: "Deskpouch reads macOS Calendar. Add your Google account in System Settings › Internet Accounts, then allow Calendars for Deskpouch.",
                        button: "Open Settings", action: model.retryAccess
                    )
                case .unknown:
                    AccessCard(title: "Asking for calendar access", detail: "Allow full access in the prompt.", button: "Ask again", action: model.retryAccess)
                }
                options(model)
            }
        }
    }

    private func options(_ model: CalendarModel) -> some View {
        OptionsGroup {
            if !model.calendars.isEmpty {
                CalendarsDisclosure(model: model)
            }
            OptionRow("Show in menubar") {
                PopupPicker(
                    id: "calendar.preview",
                    selection: Binding(get: { model.settings.previewMinutes }, set: { value in model.update { $0.previewMinutes = value } }),
                    options: CalendarSettings.previewChoices,
                    title: { CalendarSettings.previewLabel($0) }
                )
            }
            OptionRow("Show title") {
                ToggleSwitch("Show title", isOn: Binding(get: { model.settings.showTitle }, set: { value in model.update { $0.showTitle = value } }))
            }
            OptionRow("Sound", detail: "When a reminder appears") {
                PopupPicker(
                    id: "calendar.sound",
                    selection: Binding(get: { model.settings.soundName ?? "" }, set: { model.chooseSound($0.isEmpty ? nil : $0) }),
                    options: soundOptions(model),
                    title: { $0.isEmpty ? "None" : $0 },
                    detail: { $0 == CalendarSettings.defaultSound ? "default" : nil }
                )
            }
            OptionRow("Join") {
                ShortcutRecorder(.press(state.calendarKey)) { kind in
                    if case .press(let combo) = kind { actions.setCalendarPressKey(combo) }
                }
            }
        }
    }

    /// None, then every alert sound; a stored sound that has since gone from disk stays listed so the popup can
    /// show it.
    private func soundOptions(_ model: CalendarModel) -> [String] {
        var names = model.sounds
        if let current = model.settings.soundName, !names.contains(current) { names.insert(current, at: 0) }
        return [""] + names
    }
}

/// "Calendars · 7 of 7" with a chevron; open, one switch per calendar. Folded by default: an account brings
/// several calendars (holidays, a phone, shared ones) that would push the options off the panel.
private struct CalendarsDisclosure: View {
    let model: CalendarModel
    @State private var open = false

    var body: some View {
        let shown = model.calendars.filter { !model.settings.hiddenCalendars.contains($0.id) }.count
        VStack(spacing: 0) {
            OptionRow("Calendars", detail: "\(shown) of \(model.calendars.count) shown") {
                Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        HStack(spacing: -3) {
                            ForEach(model.calendars.prefix(4)) { cal in
                                Circle().fill(Color(hexString: cal.color) ?? Theme.Colors.tint(0.3))
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().strokeBorder(Theme.Colors.card, lineWidth: 1.5))
                            }
                        }
                        ChevronIcon().stroke(style: .icon(1.5))
                            .foregroundStyle(Theme.Colors.text.opacity(0.6))
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.tint(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.Colors.tint(0.14), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "Hide the calendar list" : "Choose calendars")
                .accessibilityLabel("Calendars")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
            }
            if open {
                VStack(spacing: 0) {
                    ForEach(model.calendars) { cal in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hexString: cal.color) ?? Theme.Colors.tint(0.3)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cal.title).font(.dp(12)).lineLimit(1)
                                if cal.account != cal.title {
                                    Text(cal.account).font(.dp(10.5)).foregroundStyle(Theme.Colors.textFaint).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            ToggleSwitch(cal.title, isOn: Binding(
                                get: { !model.settings.hiddenCalendars.contains(cal.id) },
                                set: { model.setCalendar(cal.id, visible: $0) }
                            ))
                        }
                        .frame(height: 34)
                    }
                }
                .padding(.leading, 8)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }
}

/// Today: an all-day line, then rows with a now line between the past and what is next.
private struct AgendaList: View {
    let model: CalendarModel

    var body: some View {
        let agenda = model.agenda
        let rows = agenda.todayRows
        let nowIndex = rows.firstIndex { !$0.isPast } ?? rows.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(.dp(11, .semibold)).tracking(0.66).textCase(.uppercase).foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.dp(11)).foregroundStyle(Theme.Colors.textFaint)
            }
            .padding(.horizontal, 4)
            ForEach(agenda.allDayToday) { event in
                HStack(spacing: 8) {
                    Circle().fill(Color(hexString: event.calendarColor) ?? Theme.Colors.tint(0.3)).frame(width: 6, height: 6)
                    Text("All day").foregroundStyle(Theme.Colors.textSecondary)
                    Text(event.title).foregroundStyle(Theme.Colors.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.dp(12))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Colors.tint(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.Colors.tint(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            if rows.isEmpty {
                Text("Nothing else today")
                    .font(.dp(12))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.Colors.tint(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index == nowIndex { NowLine(now: agenda.now, text: agenda.text) }
                        AgendaRow(row: row, agenda: agenda, join: { model.join(row.event) })
                    }
                    if nowIndex == rows.count { NowLine(now: agenda.now, text: agenda.text) }
                }
            }
        }
    }
}

private struct NowLine: View {
    let now: Date
    let text: CalendarText

    var body: some View {
        HStack(spacing: 6) {
            Text(text.clock(now)).font(.dp(10, .semibold)).monospacedDigit().foregroundStyle(Theme.Colors.accent)
            Circle().fill(Theme.Colors.accent).frame(width: 6, height: 6).shadow(color: Theme.Colors.accent(0.8), radius: 4)
            Rectangle().fill(LinearGradient(colors: [Theme.Colors.accent(0.7), Theme.Colors.accent(0.05)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}

private struct AgendaRow: View {
    let row: Agenda.Row
    let agenda: Agenda
    let join: @MainActor () -> Void

    var body: some View {
        let event = row.event
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(agenda.text.clock(event.start)).font(.dp(12, .medium))
                Text(agenda.text.clock(event.end)).font(.dp(11)).foregroundStyle(Theme.Colors.text.opacity(0.38))
            }
            .monospacedDigit()
            .frame(width: 40, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(Color(hexString: event.calendarColor) ?? Theme.Colors.tint(0.3)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.dp(13, .medium)).lineLimit(1)
                meta(event)
                    .font(.dp(11))
                    .foregroundStyle(Theme.Colors.textFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if event.joinable, !row.isPast {
                Button(action: join) {
                    HStack(spacing: 5) {
                        CameraIcon().stroke(style: .icon(1.5)).frame(width: 12, height: 12)
                        Text("Join").font(.dp(11, .semibold))
                    }
                    .foregroundStyle(Theme.Colors.accentInk)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule().fill(LinearGradient(colors: [Theme.Colors.accentHigh, Theme.Colors.accent], startPoint: .top, endPoint: .bottom)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Join the call")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(shape.fill(LinearGradient(colors: [Theme.Colors.accent(0.09), Theme.Colors.accent(0.02)], startPoint: .leading, endPoint: .trailing)).opacity(row.isNext ? 1 : 0))
        .overlay(shape.strokeBorder(Theme.Colors.accent(0.32), lineWidth: 1).opacity(row.isNext ? 1 : 0))
        .opacity(row.isPast ? 0.42 : 1)
    }

    /// "in 12 min · Meet · 30 min", "Grand Central Kitchen", "15 min".
    private func meta(_ event: CalendarEvent) -> Text {
        var parts: [String] = []
        if event.isMeet { parts.append("Meet") } else if let place = event.shortLocation { parts.append(place) }
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        if parts.isEmpty || event.isMeet { parts.append(minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min") }
        let rest = Text(parts.joined(separator: " · "))
        if row.isNext {
            let when = event.isRunning(at: agenda.now)
                ? agenda.text.remaining(until: event.end, from: agenda.now)
                : agenda.text.countdown(to: event.start, from: agenda.now)
            return Text(when + " · ").foregroundColor(event.isRunning(at: agenda.now) ? Theme.Colors.ok : Theme.Colors.accentHigh) + rest
        }
        return rest
    }
}

private struct AccessCard: View {
    let title: String
    let detail: String
    let button: String
    let action: @MainActor () -> Void

    var body: some View {
        ToolCard(live: false, liveColor: Theme.Colors.accent) {
            HStack(alignment: .top, spacing: 12) {
                CalendarTile()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.dp(13, .medium))
                    Text(detail).font(.dp(12)).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                RowButton(button, action: action)
            }
        }
    }
}

extension Color {
    /// "#83d754" from EventKit's calendar colour.
    init?(hexString: String?) {
        guard let hexString, hexString.hasPrefix("#"), let value = UInt32(hexString.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
