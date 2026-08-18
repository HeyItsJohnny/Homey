import SwiftUI

struct ChoreOccurrenceStatusStyle: Equatable {
    let title: String
    let color: Color
    let backgroundColor: Color

    init(occurrence: ChoreOccurrence) {
        switch occurrence.displayStatus {
        case .overdue:
            title = "Overdue"
            color = HomeyDashboardTheme.softRed
            backgroundColor = color.opacity(0.12)
        case .stored(let status):
            switch status {
            case .notStarted:
                title = "Not Started"
                color = HomeyDashboardTheme.softRed
                backgroundColor = color.opacity(0.12)
            case .inProgress:
                title = "In Progress"
                color = HomeyDashboardTheme.orangeAccent
                backgroundColor = color.opacity(0.12)
            case .awaitingApproval:
                title = "Awaiting Approval"
                color = HomeyDashboardTheme.orangeAccent
                backgroundColor = color.opacity(0.12)
            case .completed:
                title = "Completed"
                color = HomeyDashboardTheme.sageAccent
                backgroundColor = color.opacity(0.12)
            case .needsRedo:
                title = "Needs Redo"
                color = HomeyDashboardTheme.softRed
                backgroundColor = color.opacity(0.12)
            case .skipped:
                title = "Skipped"
                color = HomeyDashboardTheme.secondaryText
                backgroundColor = HomeyDashboardTheme.cardBackground
            case .cancelled:
                title = "Cancelled"
                color = HomeyDashboardTheme.secondaryText
                backgroundColor = HomeyDashboardTheme.cardBackground
            }
        }
    }
}
