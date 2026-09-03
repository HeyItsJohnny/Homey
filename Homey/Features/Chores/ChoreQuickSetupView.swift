import SwiftUI

@MainActor
struct ChoreQuickSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let homeId: UUID?
    let currentRole: HomeMemberRole?
    let timezone: String
    let members: [HomeMemberDisplay]
    let onFinished: () -> Void
    let onShowRewards: () -> Void

    @State private var step: ChoreQuickSetupStep = .areas
    @State private var areaCount = QuickSetupRoomDraft.defaultRooms.count
    @State private var rooms = QuickSetupRoomDraft.defaultRooms
    @State private var creationErrorMessage: String?
    @State private var creationPhase: QuickSetupCreationPhase = .idle
    @State private var totalChoresToCreate = 0
    @State private var completedChores = 0
    @State private var currentChoreName: String?
    @State private var currentRoomName: String?
    @State private var isCreating = false
    @State private var createdRoomCount = 0
    @State private var createdChoreCount = 0
    @State private var showExitConfirmation = false

    private let repository: ChoresRepository
    private let calendarSyncService: ChoreCalendarSyncService

    init(
        homeId: UUID?,
        currentRole: HomeMemberRole?,
        timezone: String,
        members: [HomeMemberDisplay],
        onFinished: @escaping () -> Void = {},
        onShowRewards: @escaping () -> Void = {}
    ) {
        let repository = ChoresRepository()
        self.homeId = homeId
        self.currentRole = currentRole
        self.timezone = timezone
        self.members = members
        self.repository = repository
        self.calendarSyncService = ChoreCalendarSyncService(choresRepository: repository)
        self.onFinished = onFinished
        self.onShowRewards = onShowRewards
    }

    private var sortedMembers: [HomeMemberDisplay] {
        HomeMemberDisplay.sorted(members)
    }

    private var selectedChoreCount: Int {
        rooms.reduce(0) { count, room in
            count + room.chores.filter(\.isSelected).count
        }
    }

    private var canContinue: Bool {
        switch step {
        case .areas:
            return rooms.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .chores, .schedule, .assignments, .review:
            return selectedChoreCount > 0 && assignmentsAreValid
        case .roomDetails, .complete:
            return true
        }
    }

    private var assignmentsAreValid: Bool {
        rooms.allSatisfy { room in
            room.chores.allSatisfy { chore in
                !chore.isSelected || chore.assignmentMode == .open || !chore.assigneeIds.isEmpty
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        step != .areas || areaCount != QuickSetupRoomDraft.defaultRooms.count || rooms != QuickSetupRoomDraft.defaultRooms
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    setupHeader

                    ScrollView {
                        currentStepContent
                            .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 32)
                            .padding(.vertical, 26)
                            .frame(maxWidth: 1180)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)

                    bottomNavigation
                }
            }
            .navigationTitle("Chores Quick Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        requestDismissal()
                    }
                    .disabled(isCreating)
                }
            }
            .confirmationDialog("Exit Quick Setup?", isPresented: $showExitConfirmation, titleVisibility: .visible) {
                Button("Keep Setting Up", role: .cancel) {}
                Button("Exit", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Your setup hasn't been saved yet.")
            }
        }
        .onAppear {
            syncRoomDraftCount(to: areaCount)
        }
        .onChange(of: areaCount) { _, _ in
            syncRoomDraftCount(to: areaCount)
        }
        .interactiveDismissDisabled(isCreating)
    }

    private var setupHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chores Quick Setup")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text(step.progressText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer()
            }

            ProgressView(value: Double(step.rawValue + 1), total: Double(ChoreQuickSetupStep.allCases.count))
                .tint(HomeyDashboardTheme.warmBrown)
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 32)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.74))
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch step {
        case .areas:
            areasStep
        case .roomDetails:
            roomDetailsStep
        case .chores:
            choresStep
        case .schedule:
            scheduleStep
        case .assignments:
            assignmentsStep
        case .review:
            reviewStep
        case .complete:
            completeStep
        }
    }

    private var areasStep: some View {
        QuickSetupCard {
            VStack(alignment: .leading, spacing: 22) {
                stepIntro(
                    title: "Let's set up your home",
                    body: "Start by telling Homey which rooms or areas you want to manage.",
                    systemImage: "house.fill"
                )

                Stepper(value: areaCountBinding, in: 1...20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How many areas do you want to set up?")
                            .font(.headline)
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                        Text("\(areaCount) \(areaCount == 1 ? "area" : "areas")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    }
                }

                VStack(spacing: 12) {
                    ForEach(rooms.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Area \(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            TextField("Area name", text: $rooms[index].name)
                                .textFieldStyle(QuickSetupTextFieldStyle())
                                .onChange(of: rooms[index].name) { _, newValue in
                                    rooms[index].roomType = QuickSetupRoomDraft.inferredRoomType(from: newValue)
                                }
                        }
                    }
                }
            }
        }
    }

    private var roomDetailsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Add room details",
                body: "Choose the room type, preferred cleaning day, and general cleaning rhythm for each area.",
                systemImage: "slider.horizontal.3"
            )

            LazyVGrid(columns: adaptiveColumns(minimum: 320), spacing: 16) {
                ForEach(rooms.indices, id: \.self) { index in
                    QuickSetupRoomDetailsCard(room: $rooms[index], index: index, total: rooms.count)
                }
            }
        }
    }

    private var choresStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Choose starter chores",
                body: "Regular Cleaning chores are what Homey uses to know when this room was last cleaned.",
                systemImage: "checklist"
            )

            LazyVGrid(columns: adaptiveColumns(minimum: 360), spacing: 16) {
                ForEach(rooms.indices, id: \.self) { index in
                    QuickSetupChoreSelectionCard(room: $rooms[index])
                }
            }
        }
        .onAppear(perform: applyStarterSuggestionsIfNeeded)
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Set schedule and points",
                body: "Room preferences set helpful defaults. Each chore can still have its own frequency, day, and points. Regular Cleaning chores help Homey know when the whole room was last cleaned.",
                systemImage: "calendar.badge.clock"
            )

            LazyVGrid(columns: adaptiveColumns(minimum: 390), spacing: 16) {
                ForEach(rooms.indices, id: \.self) { roomIndex in
                    QuickSetupScheduleCard(room: $rooms[roomIndex])
                }
            }
        }
    }

    private var assignmentsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Choose who handles them",
                body: "Leave chores open for anyone, or assign specific household members.",
                systemImage: "person.2.fill"
            )

            if sortedMembers.isEmpty {
                QuickSetupCard {
                    ChoreMessageState(
                        title: "No members loaded",
                        message: "You can leave chores open now and assign them later.",
                        systemImage: "person.crop.circle.badge.exclamationmark"
                    )
                }
            }

            LazyVGrid(columns: adaptiveColumns(minimum: 390), spacing: 16) {
                ForEach(rooms.indices, id: \.self) { roomIndex in
                    QuickSetupAssignmentsCard(room: $rooms[roomIndex], members: sortedMembers)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewStep: some View {
        if creationPhase.isProgressVisible {
            creationProgressStep
        } else {
            reviewContent
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Review your setup",
                body: "Nothing is created until you press Create My Chores.",
                systemImage: "doc.text.magnifyingglass"
            )

            if let creationErrorMessage {
                Text(creationErrorMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HomeyDashboardTheme.destructiveRed.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            QuickSetupCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        reviewMetric(title: "Areas", value: "\(areaCount)")
                        reviewMetric(title: "Chores", value: "\(selectedChoreCount)")
                        reviewMetric(title: "Weekly Points", value: "\(approximateWeeklyPoints)")
                    }

                    VStack(spacing: 12) {
                        ForEach(rooms) { room in
                            QuickSetupReviewRoom(room: room, memberNames: memberNames)
                        }
                    }
                }
            }
        }
    }

    private var creationProgressStep: some View {
        QuickSetupCard {
            VStack(spacing: 24) {
                Image(systemName: creationPhase.systemImage)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(creationPhase == .failed ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.warmBrown)
                    .frame(width: 104, height: 104)
                    .background(
                        (creationPhase == .failed ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.selectedSidebarBackground)
                            .opacity(creationPhase == .failed ? 0.12 : 1),
                        in: Circle()
                    )

                VStack(spacing: 8) {
                    Text(creationPhase.title)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text(creationProgressSubtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(creationPhase == .failed ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                if creationPhase == .creatingChores || creationPhase == .finishing || creationPhase == .failed {
                    ProgressView(value: Double(progressValue), total: Double(max(totalChoresToCreate, 1)))
                        .tint(creationPhase == .failed ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.warmBrown)
                        .frame(maxWidth: 560)
                        .animation(.easeInOut(duration: 0.2), value: progressValue)
                } else {
                    ProgressView()
                        .tint(HomeyDashboardTheme.warmBrown)
                }

                VStack(spacing: 6) {
                    if let currentRoomName {
                        Text(currentRoomName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    }

                    if let currentChoreName {
                        Text(currentChoreName)
                            .font(.headline)
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }

                    Text(creationPhase == .failed ? "Setup stopped before creating the remaining chores." : "This may take a moment.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var completeStep: some View {
        QuickSetupCard {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(HomeyDashboardTheme.sageAccent)
                    .frame(width: 112, height: 112)
                    .background(HomeyDashboardTheme.sageAccent.opacity(0.14), in: Circle())

                VStack(spacing: 10) {
                    Text("Your chores are ready!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text("\(createdRoomCount) \(createdRoomCount == 1 ? "room" : "rooms") and \(createdChoreCount) \(createdChoreCount == 1 ? "chore" : "chores") were created.")
                        .font(.title3)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        onShowRewards()
                        dismiss()
                    } label: {
                        Label("Set Up Rewards", systemImage: "gift.fill")
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .frame(maxWidth: 320)

                    Button {
                        onFinished()
                        dismiss()
                    } label: {
                        Text("View My Chores")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .frame(maxWidth: 320, minHeight: 52)
                            .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bottomNavigation: some View {
        HStack(spacing: 12) {
            if isCreating {
                Spacer()
                Text("Please keep this open while setup finishes.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                Spacer()
            } else if creationPhase == .failed {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 220)
                Spacer()
            } else {
                Button {
                    moveBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 160, minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(step == .areas || step == .complete ? HomeyDashboardTheme.secondaryText.opacity(0.45) : HomeyDashboardTheme.warmBrown)
                .disabled(step == .areas || step == .complete || isCreating)

                Spacer()

                if step != .complete {
                    Button {
                        moveForward()
                    } label: {
                        Text(step == .review ? "Create My Chores" : "Continue")
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 260)
                    .disabled(!canContinue || isCreating)
                }
            }
        }
        .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 32)
        .padding(.vertical, 16)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.82))
    }

    private var progressValue: Int {
        switch creationPhase {
        case .idle, .preparing, .creatingRooms:
            return 0
        case .creatingChores:
            return min(completedChores + 1, max(totalChoresToCreate, 1))
        case .finishing, .completed:
            return totalChoresToCreate
        case .failed:
            return completedChores
        }
    }

    private var creationProgressSubtitle: String {
        switch creationPhase {
        case .idle:
            return ""
        case .preparing, .creatingRooms:
            return "Preparing your rooms..."
        case .creatingChores:
            let current = min(completedChores + 1, totalChoresToCreate)
            return "Creating \(current) of \(totalChoresToCreate) \(totalChoresToCreate == 1 ? "chore" : "chores")"
        case .finishing, .completed:
            return "\(totalChoresToCreate) of \(totalChoresToCreate) \(totalChoresToCreate == 1 ? "chore" : "chores") created"
        case .failed:
            return "We couldn't finish setting up your chores. \(completedChores) of \(totalChoresToCreate) \(totalChoresToCreate == 1 ? "chore was" : "chores were") created successfully."
        }
    }

    private var approximateWeeklyPoints: Int {
        rooms.reduce(0) { total, room in
            total + room.chores
                .filter { $0.isSelected }
                .reduce(0) { $0 + $1.approximateWeeklyPoints }
        }
    }

    private var areaCountBinding: Binding<Int> {
        Binding(
            get: { areaCount },
            set: { newValue in
                areaCount = newValue
                syncRoomDraftCount(to: newValue)
            }
        )
    }

    private var memberNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: sortedMembers.map { ($0.userId, $0.displayName) })
    }

    private func stepIntro(title: String, body: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 48, height: 48)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(body)
                    .font(.body)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func adaptiveColumns(minimum: CGFloat) -> [GridItem] {
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 16)]
        }

        return [GridItem(.adaptive(minimum: minimum), spacing: 16)]
    }

    private func syncRoomDraftCount(to count: Int) {
        if rooms.count < count {
            for index in rooms.count..<count {
                rooms.append(QuickSetupRoomDraft.defaultRoom(index: index))
            }
        } else if rooms.count > count {
            rooms.removeLast(rooms.count - count)
        }
    }

    private func applyStarterSuggestionsIfNeeded() {
        for index in rooms.indices {
            guard rooms[index].chores.isEmpty else { continue }
            rooms[index].chores = QuickSetupStarterChore.catalog(for: rooms[index].roomType).map {
                QuickSetupChoreDraft(starter: $0, preferredWeekday: rooms[index].preferredCleaningWeekday)
            }
        }
    }

    private func moveBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func moveForward() {
        switch step {
        case .areas:
            normalizeAreaNames()
            step = .roomDetails
        case .roomDetails:
            applyStarterSuggestionsIfNeeded()
            step = .chores
        case .chores:
            step = .schedule
        case .schedule:
            step = .assignments
        case .assignments:
            step = .review
        case .review:
            Task {
                await createSetup()
            }
        case .complete:
            break
        }
    }

    private func normalizeAreaNames() {
        for index in rooms.indices {
            rooms[index].name = rooms[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func createSetup() async {
        guard !isCreating else { return }
        guard currentRole == .owner || currentRole == .admin else {
            creationErrorMessage = "Only an owner or admin can create chores."
            return
        }
        guard let homeId else {
            creationErrorMessage = "Select a Home before running setup."
            return
        }

        do {
            let setupRooms = rooms
            let plannedChores = try prevalidateSetupChores(homeId: homeId, setupRooms: setupRooms)

            isCreating = true
            creationPhase = .preparing
            creationErrorMessage = nil
            totalChoresToCreate = plannedChores.count
            completedChores = 0
            currentChoreName = nil
            currentRoomName = nil

            var roomIdsByDraftId: [UUID: UUID] = [:]
            var createdRooms = 0
            var createdChores = 0

            creationPhase = .creatingRooms
            for (index, room) in setupRooms.enumerated() {
                let roomId = try await repository.createRoom(
                    homeId: homeId,
                    name: room.name,
                    sortOrder: index,
                    roomType: room.roomType,
                    preferredCleaningWeekday: room.preferredCleaningWeekday,
                    preferredCleaningFrequency: room.preferredCleaningFrequency
                )
                roomIdsByDraftId[room.id] = roomId
                createdRooms += 1
            }

            for room in setupRooms {
                guard let roomId = roomIdsByDraftId[room.id] else { continue }

                for plannedChore in plannedChores where plannedChore.roomDraftId == room.id {
                    let chore = plannedChore.chore
                    creationPhase = .creatingChores
                    currentRoomName = room.name
                    currentChoreName = chore.title

                    let draft = try chore.makeTemplateDraft(
                        homeId: homeId,
                        roomId: roomId,
                        timezone: timezone
                    )
                    logQuickSetupChoreCreation(chore: chore, room: room, draft: draft)
                    let templateId = try await repository.saveTemplate(draft: draft)
                    try await repository.updateTemplateRoomCleaningMetadata(
                        templateId: templateId,
                        roomId: roomId,
                        contributesToRoomCleaning: chore.contributesToRoomCleaning
                    )
                    let through = generationEndDate(startDate: draft.startDate)
                    let occurrences = try await repository.generateOccurrences(
                        templateId: templateId,
                        through: through,
                        timezone: timezone
                    )
                    _ = try await calendarSyncService.syncMissingCalendarEvents(homeId: homeId, occurrences: occurrences)
                    createdChores += 1
                    completedChores = createdChores
                }
            }

            creationPhase = .finishing
            createdRoomCount = createdRooms
            createdChoreCount = createdChores
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(
                name: .homeyCalendarEventsDidChange,
                object: nil,
                userInfo: [HomeyCalendarRefreshReason.userInfoKey: HomeyCalendarRefreshReason.choreEditSaved]
            )
            creationErrorMessage = nil
            creationPhase = .completed
            isCreating = false
            onFinished()
            step = .complete
        } catch let error as ChoreValidationError {
            isCreating = false
            creationPhase = creationPhase == .idle ? .idle : .failed
            creationErrorMessage = error.localizedDescription
        } catch let error as ChoreRepositoryError {
            isCreating = false
            creationPhase = creationPhase == .idle ? .idle : .failed
            creationErrorMessage = error.localizedDescription
        } catch {
            isCreating = false
            creationPhase = creationPhase == .idle ? .idle : .failed
            creationErrorMessage = "Unable to create your chores. Check the setup and try again."
        }
    }

    private func prevalidateSetupChores(
        homeId: UUID,
        setupRooms: [QuickSetupRoomDraft]
    ) throws -> [QuickSetupPlannedChore] {
        try setupRooms.flatMap { room in
            try room.chores
                .filter(\.isSelected)
                .map { chore in
                    _ = try chore.makeTemplateDraft(
                        homeId: homeId,
                        roomId: room.id,
                        timezone: timezone
                    )
                    return QuickSetupPlannedChore(roomDraftId: room.id, chore: chore)
                }
        }
    }

    private func generationEndDate(startDate: Date) -> Date {
        let basis = max(Date(), startDate)
        return Calendar.current.date(
            byAdding: .day,
            value: ChoresRepository.defaultGenerationWindowDays,
            to: basis
        ) ?? basis
    }

    private func requestDismissal() {
        if step == .complete || !hasUnsavedChanges {
            dismiss()
        } else {
            showExitConfirmation = true
        }
    }

    private func logQuickSetupChoreCreation(
        chore: QuickSetupChoreDraft,
        room: QuickSetupRoomDraft,
        draft: ChoreTemplateDraft
    ) {
        #if DEBUG
        let semanticWeekday = QuickSetupWeekday(roomPreference: chore.weekday)
            ?? QuickSetupWeekday.current(timezone: timezone)
        print("========== QUICK SETUP CHORE RECURRENCE ==========")
        print("chore: \(chore.title)")
        print("room_preference_semantic_day: \(room.preferredCleaningWeekday.map { QuickSetupWeekday(roomPreference: $0)?.displayName ?? $0.displayName } ?? "No Preference")")
        print("room_stored_value: \(room.preferredCleaningWeekday?.rawValue.description ?? "nil")")
        print("draft_semantic_day: \(semanticWeekday.displayName)")
        print("draft_room_value: \(semanticWeekday.roomPreferenceValue)")
        print("swift_calendar_weekday: \(semanticWeekday.swiftCalendarWeekday)")
        print("backend_postgres_dow: \(semanticWeekday.postgresDow)")
        print("recurrence_weekdays: \(draft.weekdays.sorted())")
        print("frequency: \(draft.frequency.rawValue)")
        print("interval: \(draft.intervalValue)")
        print("==================================================")
        #endif
    }
}

private enum ChoreQuickSetupStep: Int, CaseIterable {
    case areas
    case roomDetails
    case chores
    case schedule
    case assignments
    case review
    case complete

    var progressText: String {
        "Step \(rawValue + 1) of \(Self.allCases.count)"
    }

    var previous: ChoreQuickSetupStep? {
        Self(rawValue: rawValue - 1)
    }
}

private enum QuickSetupCreationPhase: Equatable {
    case idle
    case preparing
    case creatingRooms
    case creatingChores
    case finishing
    case completed
    case failed

    var isProgressVisible: Bool {
        switch self {
        case .idle, .completed:
            return false
        case .preparing, .creatingRooms, .creatingChores, .finishing, .failed:
            return true
        }
    }

    var title: String {
        switch self {
        case .idle:
            return ""
        case .preparing, .creatingRooms, .creatingChores, .finishing:
            return "Setting up your chores..."
        case .completed:
            return "Your chores are ready!"
        case .failed:
            return "We couldn't finish setup"
        }
    }

    var systemImage: String {
        switch self {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .idle, .preparing, .creatingRooms, .creatingChores, .finishing:
            return "checklist.checked"
        }
    }
}

private struct QuickSetupPlannedChore {
    let roomDraftId: UUID
    let chore: QuickSetupChoreDraft
}

private struct QuickSetupRoomDraft: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var roomType: ChoreRoomType
    var preferredCleaningWeekday: ChorePreferredCleaningWeekday?
    var preferredCleaningFrequency: ChoreRoomCleaningFrequency?
    var chores: [QuickSetupChoreDraft] = []

    static let defaultRooms: [QuickSetupRoomDraft] = [
        QuickSetupRoomDraft(name: "Kitchen", roomType: .kitchen, preferredCleaningWeekday: .saturday, preferredCleaningFrequency: .weekly),
        QuickSetupRoomDraft(name: "Living Room", roomType: .livingRoom, preferredCleaningWeekday: .sunday, preferredCleaningFrequency: .weekly),
        QuickSetupRoomDraft(name: "Primary Bedroom", roomType: .bedroom, preferredCleaningWeekday: .sunday, preferredCleaningFrequency: .weekly),
        QuickSetupRoomDraft(name: "Kids Bedroom", roomType: .bedroom, preferredCleaningWeekday: .sunday, preferredCleaningFrequency: .weekly),
        QuickSetupRoomDraft(name: "Bathroom", roomType: .bathroom, preferredCleaningWeekday: .saturday, preferredCleaningFrequency: .weekly)
    ]

    static func defaultRoom(index: Int) -> QuickSetupRoomDraft {
        QuickSetupRoomDraft(
            name: "",
            roomType: .other,
            preferredCleaningWeekday: nil,
            preferredCleaningFrequency: .weekly
        )
    }

    static func inferredRoomType(from name: String) -> ChoreRoomType {
        let normalized = name.lowercased()
        if normalized.contains("kitchen") { return .kitchen }
        if normalized.contains("bath") { return .bathroom }
        if normalized.contains("living") { return .livingRoom }
        if normalized.contains("dining") { return .diningRoom }
        if normalized.contains("laundry") { return .laundryRoom }
        if normalized.contains("office") { return .office }
        if normalized.contains("garage") { return .garage }
        if normalized.contains("outdoor") || normalized.contains("yard") || normalized.contains("patio") { return .outdoor }
        if normalized.contains("bed") { return .bedroom }
        return .other
    }
}

private struct QuickSetupChoreDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var frequency: QuickSetupFrequency
    var weekday: ChorePreferredCleaningWeekday?
    var points: Int
    var contributesToRoomCleaning: Bool
    var isSelected: Bool
    var isCustom: Bool
    var assignmentMode: ChoreAssignmentMode = .open
    var assigneeIds: Set<UUID> = []

    init(starter: QuickSetupStarterChore, preferredWeekday: ChorePreferredCleaningWeekday?) {
        title = starter.title
        frequency = starter.frequency
        weekday = preferredWeekday
        points = starter.points
        contributesToRoomCleaning = starter.contributesToRoomCleaning
        isSelected = starter.defaultSelected
        isCustom = false
    }

    init(title: String, preferredWeekday: ChorePreferredCleaningWeekday?) {
        self.title = title
        frequency = .weekly
        weekday = preferredWeekday
        points = 10
        contributesToRoomCleaning = false
        isSelected = true
        isCustom = true
    }

    var approximateWeeklyPoints: Int {
        switch frequency {
        case .daily:
            return points * 7
        case .multipleTimesWeek:
            return points * 3
        case .weekly:
            return points
        case .everyTwoWeeks:
            return max(1, points / 2)
        case .monthly:
            return max(1, points / 4)
        }
    }

    func makeTemplateDraft(homeId: UUID, roomId: UUID, timezone: String) throws -> ChoreTemplateDraft {
        let startDate = QuickSetupDateDefaults.startDate(for: frequency, weekday: weekday, timezone: timezone)
        return try ChoreTemplateDraft(
            homeId: homeId,
            title: title,
            roomId: roomId,
            assignmentMode: assignmentMode,
            completionMode: assignmentMode == .open || assigneeIds.count <= 1 ? .single : .everyone,
            pointsValue: points,
            requiresApproval: true,
            requiresPhoto: false,
            contributesToRoomCleaning: contributesToRoomCleaning,
            frequency: frequency.choreFrequency,
            intervalValue: frequency.intervalValue,
            startDate: startDate,
            dueTime: nil,
            durationMinutes: 30,
            isAllDay: true,
            weekdays: frequency.weekdays(for: weekday, timezone: timezone),
            dayOfMonth: frequency == .monthly ? QuickSetupDateDefaults.dayOfMonth(from: startDate, timezone: timezone) : nil,
            monthOfYear: nil,
            endType: .never,
            endsOn: nil,
            occurrenceCount: nil,
            timezone: timezone,
            assigneeIds: Array(assigneeIds)
        ).validated()
    }
}

private enum QuickSetupFrequency: String, CaseIterable, Identifiable {
    case daily
    case multipleTimesWeek
    case weekly
    case everyTwoWeeks
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .multipleTimesWeek:
            return "A Few Times Per Week"
        case .weekly:
            return "Weekly"
        case .everyTwoWeeks:
            return "Every 2 Weeks"
        case .monthly:
            return "Monthly"
        }
    }

    var choreFrequency: ChoreFrequency {
        switch self {
        case .daily:
            return .daily
        case .multipleTimesWeek, .weekly, .everyTwoWeeks:
            return .weekly
        case .monthly:
            return .monthly
        }
    }

    var intervalValue: Int {
        self == .everyTwoWeeks ? 2 : 1
    }

    func weekdays(for weekday: ChorePreferredCleaningWeekday?, timezone: String) -> Set<Int> {
        switch self {
        case .multipleTimesWeek:
            return QuickSetupDateDefaults.multipleTimesWeekdays(preferredWeekday: weekday)
        case .weekly, .everyTwoWeeks:
            return [QuickSetupDateDefaults.recurrenceWeekday(from: weekday, timezone: timezone)]
        case .daily, .monthly:
            return []
        }
    }
}

private enum QuickSetupWeekday: CaseIterable {
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    init?(roomPreference: ChorePreferredCleaningWeekday?) {
        guard let roomPreference else {
            return nil
        }

        switch roomPreference {
        case .sunday:
            self = .sunday
        case .monday:
            self = .monday
        case .tuesday:
            self = .tuesday
        case .wednesday:
            self = .wednesday
        case .thursday:
            self = .thursday
        case .friday:
            self = .friday
        case .saturday:
            self = .saturday
        }
    }

    init(swiftCalendarWeekday: Int) {
        switch swiftCalendarWeekday {
        case 2:
            self = .monday
        case 3:
            self = .tuesday
        case 4:
            self = .wednesday
        case 5:
            self = .thursday
        case 6:
            self = .friday
        case 7:
            self = .saturday
        default:
            self = .sunday
        }
    }

    static func current(timezone: String) -> QuickSetupWeekday {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
        return QuickSetupWeekday(swiftCalendarWeekday: calendar.component(.weekday, from: Date()))
    }

    var displayName: String {
        switch self {
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        }
    }

    var postgresDow: Int {
        swiftCalendarWeekday - 1
    }

    var swiftCalendarWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }

    var roomPreferenceValue: Int {
        swiftCalendarWeekday
    }
}

private struct QuickSetupStarterChore: Identifiable {
    let id = UUID()
    let title: String
    let frequency: QuickSetupFrequency
    let points: Int
    let contributesToRoomCleaning: Bool
    let defaultSelected: Bool

    static func catalog(for roomType: ChoreRoomType) -> [QuickSetupStarterChore] {
        switch roomType {
        case .bedroom:
            return [
                regular("Vacuum", .weekly, 10),
                regular("Dust Surfaces", .weekly, 5),
                regular("Pick Up / Organize", .weekly, 5),
                maintenance("Change Sheets", .everyTwoWeeks, 10),
                maintenance("Clean Mirror", .weekly, 5, selected: false),
                maintenance("Clean Under Bed", .monthly, 20, selected: false)
            ]
        case .kitchen:
            return [
                regular("Wipe Counters", .daily, 5),
                regular("Clean Sink", .weekly, 10),
                regular("Sweep / Vacuum Floor", .weekly, 10),
                regular("Mop Floor", .weekly, 15),
                maintenance("Clean Microwave", .weekly, 10),
                maintenance("Wipe Appliances", .weekly, 10),
                maintenance("Clean Refrigerator", .monthly, 20, selected: false)
            ]
        case .bathroom:
            return [
                regular("Clean Toilet", .weekly, 10),
                regular("Clean Sink", .weekly, 10),
                regular("Clean Shower / Tub", .weekly, 15),
                regular("Clean Mirror", .weekly, 5),
                regular("Mop Floor", .weekly, 15)
            ]
        case .livingRoom:
            return [
                regular("Vacuum", .weekly, 10),
                regular("Dust Surfaces", .weekly, 5),
                regular("Pick Up / Organize", .weekly, 5),
                maintenance("Vacuum Furniture", .monthly, 15, selected: false),
                maintenance("Clean Windows", .monthly, 20, selected: false)
            ]
        case .diningRoom:
            return [
                regular("Wipe Table", .weekly, 5),
                regular("Sweep / Vacuum Floor", .weekly, 10),
                regular("Dust Surfaces", .weekly, 5)
            ]
        case .laundryRoom:
            return [
                regular("Sweep / Vacuum Floor", .weekly, 10),
                regular("Wipe Surfaces", .weekly, 5),
                maintenance("Clean Washer", .monthly, 20, selected: false),
                maintenance("Clean Dryer Lint Area", .weekly, 10)
            ]
        case .office:
            return [
                regular("Vacuum", .weekly, 10),
                regular("Dust Desk / Surfaces", .weekly, 5),
                regular("Pick Up / Organize", .weekly, 5)
            ]
        case .garage:
            return [
                regular("Sweep Floor", .monthly, 15),
                regular("Pick Up / Organize", .monthly, 15)
            ]
        case .outdoor:
            return [
                maintenance("Sweep Patio", .weekly, 10),
                maintenance("Pick Up Yard", .weekly, 10),
                maintenance("Water Plants", .multipleTimesWeek, 5)
            ]
        case .other:
            return [
                maintenance("Tidy Area", .weekly, 10),
                maintenance("Wipe Surfaces", .weekly, 5),
                maintenance("Pick Up / Organize", .weekly, 5)
            ]
        }
    }

    private static func regular(_ title: String, _ frequency: QuickSetupFrequency, _ points: Int, selected: Bool = true) -> QuickSetupStarterChore {
        QuickSetupStarterChore(title: title, frequency: frequency, points: points, contributesToRoomCleaning: true, defaultSelected: selected)
    }

    private static func maintenance(_ title: String, _ frequency: QuickSetupFrequency, _ points: Int, selected: Bool = true) -> QuickSetupStarterChore {
        QuickSetupStarterChore(title: title, frequency: frequency, points: points, contributesToRoomCleaning: false, defaultSelected: selected)
    }
}

private enum QuickSetupDateDefaults {
    static func recurrenceWeekday(from weekday: ChorePreferredCleaningWeekday?, timezone: String) -> Int {
        (QuickSetupWeekday(roomPreference: weekday) ?? QuickSetupWeekday.current(timezone: timezone)).postgresDow
    }

    static func startDate(
        for frequency: QuickSetupFrequency,
        weekday: ChorePreferredCleaningWeekday?,
        timezone: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent

        let today = calendar.startOfDay(for: Date())
        guard frequency.choreFrequency == .weekly, let semanticWeekday = QuickSetupWeekday(roomPreference: weekday) else {
            return today
        }

        let todayWeekday = calendar.component(.weekday, from: today)
        let offset = (semanticWeekday.swiftCalendarWeekday - todayWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func dayOfMonth(from date: Date, timezone: String) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
        return calendar.component(.day, from: date)
    }

    static func multipleTimesWeekdays(preferredWeekday: ChorePreferredCleaningWeekday?) -> Set<Int> {
        guard let semanticWeekday = QuickSetupWeekday(roomPreference: preferredWeekday) else {
            return [2, 4, 6]
        }

        let preferred = semanticWeekday.postgresDow
        let before = (preferred + 5) % 7
        let after = (preferred + 2) % 7
        return [before, preferred, after]
    }
}

private struct QuickSetupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .shadow(color: HomeyDashboardTheme.shadow.opacity(0.10), radius: 12, x: 0, y: 8)
    }
}

private struct QuickSetupRoomDetailsCard: View {
    @Binding var room: QuickSetupRoomDraft
    let index: Int
    let total: Int

    var body: some View {
        QuickSetupCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room \(index + 1) of \(total)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    Text(room.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        roomTypePicker
                        cleaningDayPicker
                        frequencyPicker
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        roomTypePicker
                        cleaningDayPicker
                        frequencyPicker
                    }
                }
            }
        }
    }

    private var roomTypePicker: some View {
        quickSetupPickerField(title: "Room Type") {
            Picker(selection: $room.roomType) {
                ForEach(ChoreRoomType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            } label: {
                quickSetupPickerValue(room.roomType.displayName)
            }
            .pickerStyle(.menu)
        }
    }

    private var cleaningDayPicker: some View {
        quickSetupPickerField(title: "Cleaning Day") {
            Picker(selection: $room.preferredCleaningWeekday) {
                Text("No Preference").tag(nil as ChorePreferredCleaningWeekday?)
                ForEach(ChorePreferredCleaningWeekday.allCases) { weekday in
                    Text(weekday.displayName).tag(weekday as ChorePreferredCleaningWeekday?)
                }
            } label: {
                quickSetupPickerValue(room.preferredCleaningWeekday?.displayName ?? "No Preference")
            }
            .pickerStyle(.menu)
        }
    }

    private var frequencyPicker: some View {
        quickSetupPickerField(title: "Frequency") {
            Picker(selection: $room.preferredCleaningFrequency) {
                Text("Custom / No Preference").tag(nil as ChoreRoomCleaningFrequency?)
                ForEach(ChoreRoomCleaningFrequency.allCases) { frequency in
                    Text(frequency.quickSetupDisplayName).tag(frequency as ChoreRoomCleaningFrequency?)
                }
            } label: {
                quickSetupPickerValue(room.preferredCleaningFrequency?.quickSetupDisplayName ?? "Custom / No Preference")
            }
            .pickerStyle(.menu)
        }
    }

    private func quickSetupPickerField<PickerContent: View>(
        title: String,
        @ViewBuilder picker: () -> PickerContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            picker()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground.opacity(0.54), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }

    private func quickSetupPickerValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 4)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .contentShape(Rectangle())
    }
}

private struct QuickSetupChoreSelectionCard: View {
    @Binding var room: QuickSetupRoomDraft
    @State private var customTitle = ""

    var body: some View {
        QuickSetupCard {
            VStack(alignment: .leading, spacing: 16) {
                roomHeader
                choreGroup(title: "Regular Cleaning", choreIds: regularChoreIds)
                choreGroup(title: "Extra / Maintenance", choreIds: maintenanceChoreIds)

                HStack(spacing: 10) {
                    TextField("Custom chore", text: $customTitle)
                        .textFieldStyle(QuickSetupTextFieldStyle())
                    Button {
                        addCustomChore()
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(HomeyDashboardTheme.warmBrown, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text("Cleaning Day: \(room.preferredCleaningWeekday?.displayName ?? "No Preference")")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private func choreGroup(title: String, choreIds: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            ForEach(choreIds, id: \.self) { choreId in
                if let index = room.chores.firstIndex(where: { $0.id == choreId }) {
                    choreRow(index: index)
                }
            }
        }
    }

    private func choreRow(index: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                room.chores[index].isSelected.toggle()
            } label: {
                Image(systemName: room.chores[index].isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(room.chores[index].isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
            }
            .buttonStyle(.plain)

            TextField("Chore", text: $room.chores[index].title)
                .textFieldStyle(QuickSetupTextFieldStyle())

            if room.chores[index].isCustom {
                Button {
                    remove(room.chores[index])
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var regularChoreIds: [UUID] {
        room.chores.filter(\.contributesToRoomCleaning).map(\.id)
    }

    private var maintenanceChoreIds: [UUID] {
        room.chores.filter { !$0.contributesToRoomCleaning }.map(\.id)
    }

    private func addCustomChore() {
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        room.chores.append(QuickSetupChoreDraft(title: title, preferredWeekday: room.preferredCleaningWeekday))
        customTitle = ""
    }

    private func remove(_ chore: QuickSetupChoreDraft) {
        room.chores.removeAll { $0.id == chore.id }
    }
}

private struct QuickSetupScheduleCard: View {
    @Binding var room: QuickSetupRoomDraft

    private var selectedChoreIndices: [Int] {
        room.chores.indices.filter { room.chores[$0].isSelected }
    }

    var body: some View {
        QuickSetupCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(room.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                ForEach(selectedChoreIndices, id: \.self) { choreIndex in
                    choreScheduleRow(choreIndex: choreIndex)
                }
            }
        }
    }

    private func choreScheduleRow(choreIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(room.chores[choreIndex].title)
                .font(.headline)
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            HStack(spacing: 10) {
                Picker("Frequency", selection: $room.chores[choreIndex].frequency) {
                    ForEach(QuickSetupFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                if room.chores[choreIndex].frequency.choreFrequency == .weekly {
                    Picker("Day", selection: $room.chores[choreIndex].weekday) {
                        Text("Today").tag(nil as ChorePreferredCleaningWeekday?)
                        ForEach(ChorePreferredCleaningWeekday.allCases) { weekday in
                            Text(weekday.displayName).tag(weekday as ChorePreferredCleaningWeekday?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Stepper("\(room.chores[choreIndex].points) Points", value: $room.chores[choreIndex].points, in: 0...100, step: 5)
            }
            .font(.subheadline)

            Toggle("Regular Cleaning", isOn: $room.chores[choreIndex].contributesToRoomCleaning)
                .font(.subheadline.weight(.semibold))
                .tint(HomeyDashboardTheme.warmBrown)
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuickSetupAssignmentsCard: View {
    @Binding var room: QuickSetupRoomDraft
    let members: [HomeMemberDisplay]

    private var selectedChoreIndices: [Int] {
        room.chores.indices.filter { room.chores[$0].isSelected }
    }

    var body: some View {
        QuickSetupCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(room.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    Spacer()
                    Menu("Apply") {
                        Button("Leave all open") {
                            applyOpenToRoom()
                        }
                        if !members.isEmpty {
                            Button("Assign all to current member") {
                                applyCurrentMemberToRoom()
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                ForEach(selectedChoreIndices, id: \.self) { choreIndex in
                    assignmentRow(choreIndex: choreIndex)
                }
            }
        }
    }

    private func assignmentRow(choreIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(room.chores[choreIndex].title)
                .font(.headline)
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Picker("Assignment", selection: $room.chores[choreIndex].assignmentMode) {
                Text("Leave Open").tag(ChoreAssignmentMode.open)
                Text("Assign People").tag(ChoreAssignmentMode.assigned)
            }
            .pickerStyle(.segmented)
            .onChange(of: room.chores[choreIndex].assignmentMode) { _, mode in
                if mode == .open {
                    room.chores[choreIndex].assigneeIds = []
                }
            }

            if room.chores[choreIndex].assignmentMode == .assigned {
                if members.isEmpty {
                    Text("No household members are available.")
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                } else {
                    ForEach(members) { member in
                        Button {
                            toggle(member.userId, choreIndex: choreIndex)
                        } label: {
                            HStack {
                                AvatarView(
                                    imageURL: member.avatarURL,
                                    initials: member.initials,
                                    size: 30,
                                    showsShadow: false,
                                    accessibilityLabel: "\(member.displayName) avatar"
                                )
                                Text(member.displayName)
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                                Spacer()
                                Image(systemName: room.chores[choreIndex].assigneeIds.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(room.chores[choreIndex].assigneeIds.contains(member.userId) ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func applyOpenToRoom() {
        for index in room.chores.indices where room.chores[index].isSelected {
            room.chores[index].assignmentMode = .open
            room.chores[index].assigneeIds = []
        }
    }

    private func applyCurrentMemberToRoom() {
        guard let currentMember = members.first(where: \.isCurrentUser) ?? members.first else { return }
        for index in room.chores.indices where room.chores[index].isSelected {
            room.chores[index].assignmentMode = .assigned
            room.chores[index].assigneeIds = [currentMember.userId]
        }
    }

    private func toggle(_ userId: UUID, choreIndex: Int) {
        if room.chores[choreIndex].assigneeIds.contains(userId) {
            room.chores[choreIndex].assigneeIds.remove(userId)
        } else {
            room.chores[choreIndex].assigneeIds.insert(userId)
        }
    }
}

private struct QuickSetupReviewRoom: View {
    let room: QuickSetupRoomDraft
    let memberNames: [UUID: String]

    private var selectedChores: [QuickSetupChoreDraft] {
        room.chores.filter(\.isSelected)
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedChores) { chore in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: chore.contributesToRoomCleaning ? "checkmark.seal.fill" : "circle")
                            .foregroundStyle(chore.contributesToRoomCleaning ? HomeyDashboardTheme.sageAccent : HomeyDashboardTheme.secondaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chore.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)
                            Text("\(chore.frequency.displayName) - \(chore.weekday?.displayName ?? "Today") - \(chore.points) pts - \(assignmentText(for: chore))")
                                .font(.caption)
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.headline)
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    Text("\(room.preferredCleaningWeekday?.displayName ?? "No preferred day") - \(selectedChores.count) chores")
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func assignmentText(for chore: QuickSetupChoreDraft) -> String {
        if chore.assignmentMode == .open {
            return "Open"
        }

        let names = chore.assigneeIds.compactMap { memberNames[$0] }
        return names.isEmpty ? "Needs assignee" : names.joined(separator: ", ")
    }
}

private struct QuickSetupTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .foregroundStyle(HomeyDashboardTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(HomeyDashboardTheme.appBackground.opacity(0.64), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
    }
}

private extension ChoreRoomCleaningFrequency {
    var quickSetupDisplayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .multipleTimesWeek:
            return "A Few Times Per Week"
        case .weekly:
            return "Weekly"
        case .everyTwoWeeks:
            return "Every 2 Weeks"
        case .monthly:
            return "Monthly"
        case .custom:
            return "Custom / No Preference"
        }
    }
}

#Preview {
    ChoreQuickSetupView(
        homeId: UUID(),
        currentRole: .owner,
        timezone: TimeZone.autoupdatingCurrent.identifier,
        members: []
    )
}
