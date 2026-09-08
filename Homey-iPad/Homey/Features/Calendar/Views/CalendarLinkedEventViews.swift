import SwiftUI

struct CalendarLinkedEventColorResolver {
    static func color(
        for event: CalendarEvent,
        presentation: CalendarLinkedEventPresentation?,
        categories: [CalendarCategory]
    ) -> Color {
        if let chore = presentation?.chore {
            return chore.statusStyle.color
        }

        if presentation?.plannedMeal != nil {
            return CalendarEventColorResolver.color(for: event, categories: categories, fallback: HomeyDashboardTheme.sageAccent)
        }

        return CalendarEventColorResolver.color(for: event, categories: categories)
    }
}

struct CalendarLinkedEventChip: View {
    let presentation: CalendarLinkedEventPresentation
    let categories: [CalendarCategory]

    var body: some View {
        switch presentation.content {
        case .meal(let plannedMeal):
            MealLinkedCalendarChip(plannedMeal: plannedMeal, categories: categories)
        case .chore(let chore):
            ChoreLinkedCalendarChip(chore: chore)
        }
    }
}

struct CalendarLinkedAgendaEventRow: View {
    let presentation: CalendarLinkedEventPresentation
    let categories: [CalendarCategory]

    var body: some View {
        switch presentation.content {
        case .meal(let plannedMeal):
            MealLinkedAgendaEventRow(plannedMeal: plannedMeal, categories: categories)
        case .chore(let chore):
            ChoreLinkedAgendaEventRow(chore: chore)
        }
    }
}

private struct MealLinkedCalendarChip: View {
    let plannedMeal: PlannedMeal
    let categories: [CalendarCategory]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            mealThumbnail(size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(plannedMeal.meal.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(plannedMeal.mealType.displayName) · \(timeText(for: plannedMeal.calendarEvent))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(HomeyDashboardTheme.sageAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.sageAccent).opacity(0.62), lineWidth: 1.3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plannedMeal.meal.name), \(plannedMeal.mealType.displayName), \(timeText(for: plannedMeal.calendarEvent))")
    }

    @ViewBuilder
    private func mealThumbnail(size: CGFloat) -> some View {
        if let signedPhotoURL = plannedMeal.signedPhotoURL {
            AsyncImage(url: signedPhotoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackThumbnail
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            fallbackThumbnail
                .frame(width: size, height: size)
        }
    }

    private var fallbackThumbnail: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(HomeyDashboardTheme.sageAccent.opacity(0.16))
            .overlay {
                Image(systemName: plannedMeal.mealType.systemImageName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.sageAccent)
            }
    }
}

private struct ChoreLinkedCalendarChip: View {
    let chore: ChoreCalendarEventPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chore.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(chore.statusStyle.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(chore.statusStyle.color)
                    .lineLimit(1)

                Text(timeText(for: chore.occurrence))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(chore.statusStyle.backgroundColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(chore.statusStyle.color.opacity(0.62), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chore.title), \(chore.statusStyle.title)")
    }
}

private struct MealLinkedAgendaEventRow: View {
    let plannedMeal: PlannedMeal
    let categories: [CalendarCategory]

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            MealLinkedAgendaThumbnail(plannedMeal: plannedMeal)

            VStack(alignment: .leading, spacing: 7) {
                Text(plannedMeal.meal.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Label(plannedMeal.mealType.displayName, systemImage: plannedMeal.mealType.systemImageName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.sageAccent))
                    .lineLimit(1)

                Text(timeText(for: plannedMeal.calendarEvent))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plannedMeal.meal.name), \(plannedMeal.mealType.displayName), \(timeText(for: plannedMeal.calendarEvent))")
    }
}

private struct MealLinkedAgendaThumbnail: View {
    let plannedMeal: PlannedMeal

    var body: some View {
        Group {
            if let signedPhotoURL = plannedMeal.signedPhotoURL {
                AsyncImage(url: signedPhotoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(HomeyDashboardTheme.sageAccent.opacity(0.16))
            .overlay {
                Image(systemName: plannedMeal.mealType.systemImageName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.sageAccent)
            }
    }
}

private struct ChoreLinkedAgendaEventRow: View {
    let chore: ChoreCalendarEventPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(chore.statusStyle.color)
                .frame(width: 8, height: 58)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(chore.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(chore.statusStyle.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(chore.statusStyle.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(chore.statusStyle.color.opacity(0.12), in: Capsule())

                    Text(chore.pointsText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)

                    Text(timeText(for: chore.occurrence))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chore.title), \(chore.statusStyle.title)")
    }
}

private func timeText(for event: CalendarEvent) -> String {
    if event.isAllDay {
        return "All day"
    }

    return "\(LinkedCalendarEventFormatters.eventTime.string(from: event.occurrenceStartsAt)) - \(LinkedCalendarEventFormatters.eventTime.string(from: event.occurrenceEndsAt))"
}

private func timeText(for occurrence: ChoreOccurrence) -> String {
    if occurrence.isAllDay {
        return "All day"
    }

    return occurrence.dueAt.formatted(date: .omitted, time: .shortened)
}

private enum LinkedCalendarEventFormatters {
    static let eventTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
