import SwiftUI
import DeskBotCore

/// C# RemindersPanel: сарын calendar (Даваагаас) + reminder нэмэх / дуусгах / устгах.
/// Бүх өгөгдөл local (reminders.json).
struct RemindersPanel: View {
    let deps: ControlCenterDeps

    @State private var month: (year: Int, month: Int)
    @State private var selected: CalendarDay
    @State private var title = ""
    @State private var time = ""
    @State private var error: String?

    private var tz: TimeZone { .current }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    init(deps: ControlCenterDeps) {
        self.deps = deps
        let today = CalendarDay(.now, in: .current)
        _month = State(initialValue: (today.year, today.month))
        _selected = State(initialValue: today)
        _time = State(initialValue: Fmt.time.string(from: Date().addingTimeInterval(30 * 60)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            calendarCard.frame(width: 236)
            VStack(alignment: .leading, spacing: 8) {
                form
                list
            }
        }
    }

    // MARK: Calendar

    private var calendarCard: some View {
        let today = CalendarDay(.now, in: tz)
        let days = CalendarMonth.grid(year: month.year, month: month.month, calendar: calendar)
        let first = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .now
        let busy = Set(deps.reminders.book.active.map { CalendarDay($0.dueAt, in: tz) })
        return Card(padding: 10) {
            VStack(spacing: 4) {
                HStack {
                    Text(Fmt.monthYear.string(from: first)).font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text)
                    Spacer()
                    navButton("chevron.left") { month = CalendarMonth.shift(year: month.year, month: month.month, by: -1) }
                    navButton("chevron.right") { month = CalendarMonth.shift(year: month.year, month: month.month, by: 1) }
                }
                .padding(.bottom, 2)
                let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
                LazyVGrid(columns: cols, spacing: 0) {
                    ForEach(["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], id: \.self) {
                        Text($0).font(.system(size: 9.5)).foregroundStyle(CC.muted).frame(height: 16)
                    }
                    ForEach(days, id: \.self) { day in
                        dayCell(day, inMonth: day.month == month.month, isToday: day == today,
                                isSelected: day == selected, hasItems: busy.contains(day))
                    }
                }
            }
        }
    }

    private func navButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(CC.secondary)
                .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: CalendarDay, inMonth: Bool, isToday: Bool, isSelected: Bool, hasItems: Bool) -> some View {
        Button {
            selected = day
            if !inMonth { month = (day.year, day.month) }
            error = nil
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? CC.accent.opacity(0.25) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isToday ? CC.accent : .clear, lineWidth: 1))
                Text("\(day.day)")
                    .font(.system(size: 11))
                    .foregroundStyle(inMonth ? CC.text : CC.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if hasItems { Circle().fill(CC.amber).frame(width: 4, height: 4).padding(.bottom, 2) }
            }
            .frame(height: 27)
            .padding(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Form

    private var selectedLabel: String {
        let today = CalendarDay(.now, in: tz)
        if selected == today { return "Today" }
        let d = calendar.date(from: DateComponents(year: selected.year, month: selected.month, day: selected.day)) ?? .now
        return Fmt.shortDay.string(from: d)
    }

    private var form: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("New reminder…", text: $title).field().onSubmit(add)
                HStack(spacing: 6) {
                    TextField("HH:mm", text: $time).field().frame(width: 64).onSubmit(add)
                    Text(selectedLabel).font(.system(size: 11.5)).foregroundStyle(CC.secondary)
                    Spacer()
                    SmallButton("Add", prominent: true, action: add)
                }
                HStack(spacing: 6) {
                    SmallButton("+15 min") { quick(minutes: 15) }
                    SmallButton("+1 hour") { quick(minutes: 60) }
                    SmallButton("Tomorrow 09:00") {
                        selected = CalendarDay(Date().addingTimeInterval(86_400), in: tz)
                        month = (selected.year, selected.month)
                        time = "09:00"
                    }
                }
                if let error { Text(error).font(.system(size: 11)).foregroundStyle(CC.danger) }
                if let e = deps.reminders.lastSaveError {
                    Text("Save failed: \(e)").font(.system(size: 11)).foregroundStyle(CC.danger)
                }
            }
        }
    }

    private func add() {
        guard let due = ReminderInput.parseTime(time, on: selected, in: tz) else {
            error = "Time must be HH:mm (00:00–23:59)."
            return
        }
        submit(due)
    }

    private func quick(minutes: Double) {
        submit(Date().addingTimeInterval(minutes * 60))
    }

    private func submit(_ due: Date) {
        do {
            try deps.reminders.add(title, dueAt: due)
            title = ""
            error = nil
            let day = CalendarDay(due, in: tz)
            selected = day
            month = (day.year, day.month)
        } catch ReminderError.emptyTitle {
            error = "Enter a title first."
        } catch ReminderError.dueInPast {
            error = "That time has already passed."
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: List

    private var list: some View {
        let items = deps.reminders.book.onDate(selected, in: tz).filter { !$0.done }
        return VStack(alignment: .leading, spacing: 4) {
            SectionTitle("\(selectedLabel) · \(items.count)")
            if items.isEmpty {
                Caption("No reminders for this day.").padding(.top, 4)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(items) { r in row(r) }
                }
            }
        }
    }

    private func row(_ r: Reminder) -> some View {
        HStack(spacing: 8) {
            Text(Fmt.time.string(from: r.dueAt))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(r.fired ? CC.amber : CC.accent)
            Text(r.title).font(.system(size: 12)).foregroundStyle(CC.text).lineLimit(1)
            if r.fired {
                Text("DUE").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(CC.amber))
            }
            Spacer(minLength: 4)
            iconButton("checkmark", help: "Done") { deps.reminders.complete(r.id) }
            iconButton("trash", help: "Delete") { deps.reminders.remove(r.id) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(CC.card))
    }

    private func iconButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(CC.secondary)
                .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
