import SwiftUI
import UserNotifications
import TeliaCore

// MARK: - Today card (Dagens prioriteringar)
//
// One honest glance at the shift: follow-ups due/overdue, today's daily
// target from the active goal, today's events, expiring verified campaigns
// and one rule-based recommendation. Every number is real saved data.

struct TodayCard: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @EnvironmentObject private var salesGoals: SalesGoalStore
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var calendarSync: CalendarSyncStore
    @EnvironmentObject private var campaigns: CampaignStore

    @State private var showBrief = false
    @State private var showFollowUpAdd = false

    private var cal: Calendar { CalendarEngine.workCalendar() }

    private var groups: FollowUpEngine.Groups {
        FollowUpEngine.group(followUps.records, calendar: cal)
    }

    private var primarySnapshot: SalesGoalSnapshot? {
        salesGoals.goals
            .map { SalesGoalEngine.snapshot(goal: $0, calendar: cal, plannedShiftDates: shiftDays) }
            .filter { $0.status != .completed && $0.status != .exceeded }
            .min { a, b in
                (a.goal.targetDate.timeIntervalSinceNow) < (b.goal.targetDate.timeIntervalSinceNow)
            }
    }

    private var shiftDays: [Date] {
        let horizon = cal.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        var days = Set<Date>()
        for event in schedule.events where event.kind == .shift {
            for occurrence in CalendarEngine.occurrences(of: event, between: Date.distantPast, and: horizon, calendar: cal) {
                days.insert(cal.startOfDay(for: occurrence.start))
            }
        }
        return Array(days)
    }

    private var expiringCampaigns: [BriefCampaign] {
        campaigns.activeCampaigns.compactMap { record in
            guard let end = record.endDate else { return nil }
            let daysLeft = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: end)).day ?? 0
            return (0...7).contains(daysLeft) ? BriefCampaign(title: record.title, daysLeft: daysLeft) : nil
        }
    }

    var body: some View {
        SectionCard(title: "Dagens prioriteringar", symbol: "sun.max.fill") {
            VStack(alignment: .leading, spacing: DS.Space.m) {

                // Follow-ups — the most actionable thing first.
                if groups.overdue.count > 0 || groups.dueToday.count > 0 {
                    followUpRow
                }

                // Daily target from the nearest active goal.
                if let snap = primarySnapshot {
                    targetRow(snap)
                }

                // Today's events (own shifts + imported calendars).
                if !todayEvents.isEmpty {
                    eventsRow
                }

                // Verified campaigns ending soon.
                if !expiringCampaigns.isEmpty {
                    campaignRow
                }

                // One practical, data-derived recommendation.
                if let rec = DailyBriefEngine.recommendation(
                    followUps: groups,
                    snapshots: salesGoals.goals.map {
                        SalesGoalEngine.snapshot(goal: $0, calendar: cal, plannedShiftDates: shiftDays)
                    },
                    expiringCampaigns: expiringCampaigns
                ) {
                    recommendationRow(rec)
                }

                // Briefing + quick follow-up — the two fastest actions.
                HStack(spacing: DS.Space.s) {
                    Button {
                        Haptics.tap()
                        showBrief = true
                    } label: {
                        Label("Dagens brief", systemImage: "doc.text.magnifyingglass")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Purple.base)

                    Button {
                        Haptics.tap()
                        showFollowUpAdd = true
                    } label: {
                        Label("Kolla senare", systemImage: "plus")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(DS.Orange.base)
                }
            }
        }
        .sheet(isPresented: $showBrief) {
            DailyBriefSheet()
        }
        .sheet(isPresented: $showFollowUpAdd) {
            FollowUpQuickAddSheet()
        }
    }

    // MARK: Rows

    private var followUpRow: some View {
        NavigationLink {
            FollowUpListView()
        } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: groups.overdue.count > 0 ? "exclamationmark.circle.fill" : "person.crop.circle.badge.clock")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(groups.overdue.count > 0 ? DS.negative : DS.Orange.base)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill((groups.overdue.count > 0 ? DS.negative : DS.Orange.base).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(followUpHeadline)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Kunduppföljningar — tryck för att öppna")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var followUpHeadline: String {
        if groups.overdue.count > 0 && groups.dueToday.count > 0 {
            return "\(groups.overdue.count) försenade · \(groups.dueToday.count) idag"
        }
        if groups.overdue.count > 0 { return "\(groups.overdue.count) försenade uppföljningar" }
        return "\(groups.dueToday.count) kunder att kolla idag"
    }

    private func targetRow(_ snap: SalesGoalSnapshot) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: "target")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(DS.Purple.base)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(DS.Purple.base.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.goal.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text("\(snap.goal.category.isWholeUnit ? "\(snap.roundedUpPerDay) st" : SalesGoalEngine.formatNumber(snap.requiredPerDay, whole: false) + " kr")/dag · \(Int(snap.remaining)) kvar av \(Int(snap.goal.totalTarget))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            paceChip(snap.pace)
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).fill(DS.Surface.inset))
    }

    private func paceChip(_ pace: SalesGoalPace) -> some View {
        let tint: Color = pace == .behind ? DS.negative : pace == .ahead ? .green : DS.Purple.base
        return Chip(text: pace.displayName, color: tint)
    }

    private var todayEvents: [BriefEvent] {
        var events: [BriefEvent] = CalendarEngine
            .events(on: Date(), from: schedule.events, calendar: cal)
            .map { BriefEvent(title: $0.title, start: $0.start, origin: $0.kind.displayName) }
        events.append(contentsOf: calendarSync.externalEvents(on: Date(), calendar: cal).map {
            BriefEvent(title: $0.title, start: $0.start, origin: $0.provider.displayName)
        })
        return events.sorted { $0.start < $1.start }
    }

    private var eventsRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(Array(todayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                HStack(spacing: DS.Space.m) {
                    Text(Format.time.string(from: event.start))
                        .font(.system(.caption, design: .rounded).monospaced().weight(.semibold))
                        .foregroundStyle(DS.Purple.base)
                        .frame(width: 44, alignment: .leading)
                    Text(event.title)
                        .font(.system(.subheadline, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(event.origin)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).fill(DS.Surface.inset))
    }

    private var campaignRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(expiringCampaigns.prefix(2), id: \.title) { campaign in
                HStack(spacing: DS.Space.m) {
                    Image(systemName: "tag.fill")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(DS.Orange.base)
                    Text(campaign.title)
                        .font(.system(.subheadline, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(campaign.daysLeft <= 0 ? "Utgått" : "\(campaign.daysLeft) d kvar")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(campaign.daysLeft <= 1 ? DS.negative : DS.Orange.base)
                }
            }
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).fill(DS.Surface.inset))
    }

    private func recommendationRow(_ rec: BriefItem) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: rec.icon)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(AnyShapeStyle(DS.heroGradient)))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(rec.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(DS.Surface.tintGradient)
        )
    }
}

// MARK: - Daily brief sheet

struct DailyBriefSheet: View {
    @EnvironmentObject private var followUps: FollowUpStore
    @EnvironmentObject private var salesGoals: SalesGoalStore
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var calendarSync: CalendarSyncStore
    @EnvironmentObject private var campaigns: CampaignStore
    @Environment(\.dismiss) private var dismiss

    private var cal: Calendar { CalendarEngine.workCalendar() }

    private var brief: DailyBrief {
        let groups = FollowUpEngine.group(followUps.records, calendar: cal)
        let horizon = cal.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        var shiftDays = Set<Date>()
        for event in schedule.events where event.kind == .shift {
            for occurrence in CalendarEngine.occurrences(of: event, between: Date.distantPast, and: horizon, calendar: cal) {
                shiftDays.insert(cal.startOfDay(for: occurrence.start))
            }
        }
        let snapshots = salesGoals.goals.map {
            SalesGoalEngine.snapshot(goal: $0, calendar: cal, plannedShiftDates: Array(shiftDays))
        }

        var events: [BriefEvent] = CalendarEngine
            .upcoming(from: schedule.events, after: cal.startOfDay(for: Date()), limit: 30, calendar: cal)
            .map { BriefEvent(title: $0.title, start: $0.start, origin: $0.kind.displayName) }
        events.append(contentsOf: calendarSync.externalUpcoming(after: Date(), limit: 30).map {
            BriefEvent(title: $0.title, start: $0.start, origin: $0.provider.displayName)
        })
        events.sort { $0.start < $1.start }

        let expiring = campaigns.activeCampaigns.compactMap { record -> BriefCampaign? in
            guard let end = record.endDate else { return nil }
            let daysLeft = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: end)).day ?? 0
            return (0...7).contains(daysLeft) ? BriefCampaign(title: record.title, daysLeft: daysLeft) : nil
        }

        return DailyBriefEngine.build(
            date: Date(),
            calendar: cal,
            goalSnapshots: snapshots,
            followUps: groups,
            events: events,
            expiringCampaigns: expiring
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let rec = brief.recommendation {
                    Section {
                        HStack(alignment: .top, spacing: DS.Space.m) {
                            Image(systemName: rec.icon)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 11).fill(AnyShapeStyle(DS.heroGradient)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rec.title)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                Text(rec.detail)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(rec.source.label)
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundStyle(DS.Purple.base)
                            }
                        }
                        .padding(.vertical, 6)
                    } header: {
                        Text("Dagens rekommendation")
                    }
                }

                briefSection("Säljmål", items: brief.goalItems, emptyText: "Inget aktivt säljmål — skapa ett i Schema → Säljmål.")
                briefSection("Kunduppföljningar", items: brief.followUpItems, emptyText: "Inga uppföljningar att visa.")
                briefSection("Händelser", items: brief.eventItems, emptyText: "Inga händelser.")
                briefSection("Kampanjer som snart slutar", items: brief.campaignItems, emptyText: "Inga verifierade kampanjer slutar inom en vecka.")

                Section {
                    Text("Källor märks med Uppmätt (inmatade siffror), Beräknat (uträknat från dina inmatningar) och Verifierat (kontrollerad kampanjdata). Saknas information visas det — appen hittar aldrig på innehåll.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Dagens brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func briefSection(_ title: String, items: [BriefItem], emptyText: String) -> some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: item.icon)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(DS.Purple.base)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text(item.detail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.source.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
