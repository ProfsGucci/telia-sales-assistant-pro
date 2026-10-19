import Foundation

// MARK: - Daily sales briefing (Core engine)
//
// Builds the "Dagens brief" content from REAL data only: the user's manual
// goals, saved follow-ups, configured events and verified campaigns. Every
// item is labeled with its data source so the UI can distinguish measured,
// manually entered, calculated and verified information. Nothing here
// invents figures — when inputs are missing the brief says so.

/// Where a briefing item's information comes from.
public enum BriefSource: String, Codable, CaseIterable, Sendable {
    case measured, manual, calculated, verified

    public var label: String {
        switch self {
        case .measured: return "Uppmätt"
        case .manual: return "Inmatat"
        case .calculated: return "Beräknat"
        case .verified: return "Verifierat"
        }
    }
}

public struct BriefItem: Hashable, Identifiable, Sendable {
    public let id: String
    /// SF Symbol name.
    public let icon: String
    public let title: String
    public let detail: String
    public let source: BriefSource

    public init(id: String = UUID().uuidString, icon: String,
                title: String, detail: String, source: BriefSource) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.source = source
    }
}

// MARK: Inputs (small, app-agnostic values so Core stays testable)

public struct BriefEvent: Hashable, Sendable {
    public let title: String
    public let start: Date
    /// "Pass" (app shift) or a provider name for imported events.
    public let origin: String

    public init(title: String, start: Date, origin: String) {
        self.title = title
        self.start = start
        self.origin = origin
    }
}

public struct BriefCampaign: Hashable, Sendable {
    public let title: String
    /// Verified days until the campaign's verified end date.
    public let daysLeft: Int

    public init(title: String, daysLeft: Int) {
        self.title = title
        self.daysLeft = daysLeft
    }
}

// MARK: Brief

public struct DailyBrief: Sendable {
    public let date: Date
    public var goalItems: [BriefItem]
    public var followUpItems: [BriefItem]
    public var eventItems: [BriefItem]
    public var campaignItems: [BriefItem]
    /// Exactly one practical, data-derived recommendation (never invented).
    public var recommendation: BriefItem?

    public var isEmpty: Bool {
        goalItems.isEmpty && followUpItems.isEmpty && eventItems.isEmpty
            && campaignItems.isEmpty && recommendation == nil
    }
}

public enum DailyBriefEngine {

    /// Builds the briefing. All inputs come from real saved data.
    public static func build(
        date: Date = Date(),
        calendar: Calendar = .current,
        goalSnapshots: [SalesGoalSnapshot],
        followUps: FollowUpEngine.Groups,
        events: [BriefEvent],
        expiringCampaigns: [BriefCampaign]
    ) -> DailyBrief {
        var brief = DailyBrief(
            date: date,
            goalItems: [],
            followUpItems: [],
            eventItems: [],
            campaignItems: [],
            recommendation: nil
        )

        // --- Goals (calculated from manual inputs) ---
        let active = goalSnapshots
            .filter { $0.status != .completed && $0.status != .exceeded }
            .prefix(3)
        for snap in active {
            let whole = snap.goal.category.isWholeUnit
            let perDay = whole
                ? "\(snap.roundedUpPerDay)"
                : SalesGoalEngine.formatNumber(snap.requiredPerDay, whole: false)
            let unit = whole ? "st" : "kr"
            brief.goalItems.append(BriefItem(
                icon: "target",
                title: snap.goal.title,
                detail: "\(formatRemaining(snap, whole: whole)) kvar · sikta \(perDay) \(unit)/dag · \(snap.remainingDays) säljdagar kvar",
                source: .calculated
            ))
        }

        // --- Follow-ups (saved data; names only, never personnummer) ---
        if followUps.overdue.count > 0 {
            brief.followUpItems.append(BriefItem(
                icon: "exclamationmark.circle.fill",
                title: "\(followUps.overdue.count) försenade uppföljningar",
                detail: "Äldst: \(followUps.overdue[0].name)",
                source: .manual
            ))
        }
        if followUps.dueToday.count > 0 {
            let names = followUps.dueToday.prefix(3).map(\.name).joined(separator: ", ")
            let more = followUps.dueToday.count > 3 ? " +\(followUps.dueToday.count - 3) till" : ""
            brief.followUpItems.append(BriefItem(
                icon: "person.crop.circle.badge.clock",
                title: "\(followUps.dueToday.count) kunder att kolla idag",
                detail: names + more,
                source: .manual
            ))
        }
        if followUps.upcoming.count > 0 {
            brief.followUpItems.append(BriefItem(
                icon: "calendar",
                title: "\(followUps.upcoming.count) kommande uppföljningar",
                detail: "Nästa: \(followUps.upcoming[0].name)",
                source: .manual
            ))
        }

        // --- Events (configured shifts + imported calendars) ---
        let upcoming = events
            .filter { $0.start >= calendar.startOfDay(for: date) }
            .sorted { $0.start < $1.start }
        let todayEvents = upcoming.filter { calendar.isDate($0.start, inSameDayAs: date) }
        if todayEvents.isEmpty && upcoming.isEmpty {
            // No events configured — state it instead of inventing any.
            brief.eventItems.append(BriefItem(
                icon: "calendar.badge.exclamationmark",
                title: "Inga händelser schemalagda",
                detail: "Lägg till pass i Schema eller anslut dina kalendrar.",
                source: .manual
            ))
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.locale = Locale(identifier: "sv_SE")
            timeFormatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "EEE d MMM HH:mm"
            for event in (todayEvents.isEmpty ? upcoming : todayEvents).prefix(3) {
                brief.eventItems.append(BriefItem(
                    icon: "clock",
                    title: event.title,
                    detail: "\(timeFormatter.string(from: event.start)) · \(event.origin)",
                    source: .manual
                ))
            }
        }

        // --- Campaigns (verified data only) ---
        for campaign in expiringCampaigns.prefix(3) {
            brief.campaignItems.append(BriefItem(
                icon: "tag.fill",
                title: campaign.title,
                detail: campaign.daysLeft <= 0
                    ? "Slutdatum har passerat — kontrollera innan du nämner den"
                    : "Slutar om \(campaign.daysLeft) dag\(campaign.daysLeft == 1 ? "" : "ar")",
                source: .verified
            ))
        }

        // --- One recommendation, rule-based from the same data ---
        brief.recommendation = recommendation(
            followUps: followUps, snapshots: goalSnapshots,
            expiringCampaigns: expiringCampaigns
        )

        return brief
    }

    /// The single practical recommendation. Priority: overdue follow-ups →
    /// today's follow-ups → behind-target goals → expiring campaigns →
    /// no goals → quiet-day default. Every branch quotes real data.
    public static func recommendation(
        followUps: FollowUpEngine.Groups,
        snapshots: [SalesGoalSnapshot],
        expiringCampaigns: [BriefCampaign]
    ) -> BriefItem? {
        if followUps.overdue.count > 0 {
            return BriefItem(
                icon: "phone.fill",
                title: "Börja dagen med uppföljningarna",
                detail: "\(followUps.overdue.count) försenade kunder väntar — ring dem innan första nya kunden.",
                source: .calculated
            )
        }
        if followUps.dueToday.count > 0 {
            return BriefItem(
                icon: "person.crop.circle.badge.checkmark",
                title: "Klara uppföljningarna tidigt",
                detail: "\(followUps.dueToday.count) kund\(followUps.dueToday.count == 1 ? "" : "er") att kolla idag — lämna ingen till eftermiddagen.",
                source: .calculated
            )
        }
        if let behind = snapshots.first(where: { $0.pace == .behind && $0.remaining > 0 }) {
            let whole = behind.goal.category.isWholeUnit
            let perDay = whole
                ? "\(behind.roundedUpPerDay) st"
                : SalesGoalEngine.formatNumber(behind.requiredPerDay, whole: false) + " kr"
            return BriefItem(
                icon: "hare.fill",
                title: "Du ligger efter schemat på \(behind.goal.title)",
                detail: "Sikta \(perDay) per säljdag resten av perioden så tar du ikapp målet.",
                source: .calculated
            )
        }
        if let soon = expiringCampaigns.first(where: { $0.daysLeft >= 0 && $0.daysLeft <= 3 }) {
            return BriefItem(
                icon: "tag.fill",
                title: "Nämn kampanjen som snart slutar",
                detail: "\(soon.title) gäller bara \(soon.daysLeft) dag\(soon.daysLeft == 1 ? "" : "ar") till — ett naturligt samtalsämne.",
                source: .verified
            )
        }
        if snapshots.filter({ $0.status != .completed && $0.status != .exceeded }).isEmpty {
            return BriefItem(
                icon: "target",
                title: "Skapa ett säljmål",
                detail: "Sätt ett mål i Schema → Säljmål så räknar appen ut din dagliga target.",
                source: .calculated
            )
        }
        return BriefItem(
            icon: "lightbulb.fill",
            title: "En verifierad kampanj per samtal",
            detail: "Kolla Kampanj Center innan första kunden och välj dagens erbjudande.",
            source: .verified
        )
    }

    private static func formatRemaining(_ snap: SalesGoalSnapshot, whole: Bool) -> String {
        whole
            ? "\(Int(snap.remaining))"
            : SalesGoalEngine.formatNumber(snap.remaining, whole: false)
    }
}
