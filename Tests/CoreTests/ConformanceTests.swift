import XCTest
@testable import TeliaCore

/// Compile-time probes mirroring the app layer's `Equatable`/`Hashable`
/// requirements on Core types. The app layer (SwiftUI code, Apple-SDK-only)
/// declares `CatalogData`, `LibraryData`, `LearningData`, … as Equatable,
/// which synthesizes conformance from these Core types. If a Core type ever
/// loses Hashable/Equatable, THIS file fails to compile on Linux — long
/// before Xcode runs — keeping the failure cheap to catch.
final class ConformanceTests: XCTestCase {

    struct ProbeCatalogData: Equatable {
        var snapshot: CatalogSnapshot?
        var changes: [PriceVerification.PriceChange]
    }

    struct ProbeLibraryData: Equatable {
        var scripts: [SavedScript]
        var notes: [PersonalNote]
        var answers: [ChatMessage]
    }

    struct ProbeLearningData: Equatable {
        var lessons: [LessonProgress]
        var answers: [QuizAnswerRecord]
        var srs: [SrsCardState]
    }

    struct ProbeScheduleData: Equatable {
        var events: [ScheduleEvent]
        var tasks: [DayTask]
    }

    struct ProbeProgressData: Equatable {
        var entries: [SalesEntry]
        var goals: Goals
        var aggregates: [DayAggregate]
    }

    func testProbesCompareEqual() {
        XCTAssertEqual(
            ProbeCatalogData(snapshot: nil, changes: []),
            ProbeCatalogData(snapshot: nil, changes: [])
        )
        XCTAssertEqual(
            ProbeLibraryData(scripts: [], notes: [], answers: []),
            ProbeLibraryData(scripts: [], notes: [], answers: [])
        )
        XCTAssertEqual(
            ProbeLearningData(lessons: [], answers: [], srs: []),
            ProbeLearningData(lessons: [], answers: [], srs: [])
        )
        XCTAssertEqual(
            ProbeScheduleData(events: [], tasks: []),
            ProbeScheduleData(events: [], tasks: [])
        )
        XCTAssertEqual(
            ProbeProgressData(entries: [], goals: Goals(), aggregates: []),
            ProbeProgressData(entries: [], goals: Goals(), aggregates: [])
        )
    }
}
