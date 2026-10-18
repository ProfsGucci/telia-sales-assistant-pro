import Foundation
import SwiftUI
import TeliaCore

// MARK: - Sales goals store (Schema → Säljmål)
//
// Manual goals only — actual progress is always a number the user typed.
// Persists on change; calculations are pure Core (SalesGoalEngine).

@MainActor
final class SalesGoalStore: ObservableObject {
    @Published var goals: [SalesGoal] {
        didSet { DataStore.save(goals) }
    }

    init() {
        self.goals = DataStore.load([SalesGoal].self) ?? []
    }

    func upsert(_ goal: SalesGoal) {
        guard SalesGoalEngine.isValid(goal: goal) else { return }
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
    }

    func delete(_ goal: SalesGoal) {
        goals.removeAll { $0.id == goal.id }
    }
}
