import SwiftUI
import Supabase
import Combine

struct ChoresMainView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneChoresViewModel()

    var body: some View {
        ScrollView {
            if model.isLoading && model.rooms.isEmpty {
                ProgressView("Loading chores…").padding(.top, 64)
            } else if let error = model.errorMessage, model.rooms.isEmpty {
                VStack(spacing: 14) {
                    HomeyErrorView(message: error)
                    Button("Try Again") { Task { await load() } }.buttonStyle(HomeyButtonStyle())
                }.padding(20).homeyCard().padding()
            } else if model.rooms.isEmpty {
                ChorePlaceholderView(title: "No rooms yet", message: "Use Add Room and Chores to set up your first room.", symbol: "door.left.hand.open")
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(model.rooms) { room in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(room.name).font(HomeyTypography.headline)
                                    Text(room.detail).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                }
                                Spacer()
                                Text("\(model.chores(for: room.id).count)").font(.headline).foregroundStyle(HomeyColors.primary)
                            }
                            let chores = model.chores(for: room.id)
                            if chores.isEmpty { Text("No chores in this room").font(.subheadline).foregroundStyle(HomeyColors.secondaryText) }
                            ForEach(chores) { chore in
                                HStack(spacing: 10) {
                                    Image(systemName: "circle").foregroundStyle(HomeyColors.primary)
                                    Text(chore.title)
                                    Spacer()
                                    Text("\(chore.pointsValue) pts").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
                                }.padding(.top, 3)
                            }
                        }.homeyCard()
                    }
                }.padding(16)
            }
        }
        .refreshable { await load() }
        .task(id: appSession.activeHome?.id) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { _ in Task { await load() } }
    }

    private func load() async { await model.load(homeID: appSession.activeHome?.id) }
}

private struct PhoneChoreRoom: Decodable, Identifiable {
    let id: UUID
    let name: String
    let roomType: String?
    let preferredCleaningWeekday: Int?
    var detail: String {
        let type = (roomType ?? "other").replacingOccurrences(of: "_", with: " ").capitalized
        guard let weekday = preferredCleaningWeekday, (1...7).contains(weekday) else { return type }
        return "\(type) • \(Calendar.current.weekdaySymbols[weekday - 1])"
    }
    enum CodingKeys: String, CodingKey { case id, name, roomType = "room_type", preferredCleaningWeekday = "preferred_cleaning_weekday" }
}

private struct PhoneChoreTemplate: Decodable, Identifiable {
    let id: UUID
    let roomID: UUID?
    let title: String
    let pointsValue: Int
    enum CodingKeys: String, CodingKey { case id, roomID = "room_id", title, pointsValue = "points_value" }
}

@MainActor
private final class PhoneChoresViewModel: ObservableObject {
    @Published var rooms: [PhoneChoreRoom] = []
    @Published var templates: [PhoneChoreTemplate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let client = SupabaseManager.shared.client

    func chores(for roomID: UUID) -> [PhoneChoreTemplate] { templates.filter { $0.roomID == roomID } }
    func load(homeID: UUID?) async {
        guard let homeID else { rooms = []; templates = []; return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            // Match the working iPad ChoresRepository.fetchRooms contract and
            // query only the deployed room fields this screen displays.
            let loadedRooms: [PhoneChoreRoom] = try await client
                .from("chore_rooms")
                .select("id,name,room_type,preferred_cleaning_weekday")
                .eq("home_id", value: homeID.uuidString)
                .order("sort_order")
                .execute()
                .value
            // Match ChoresRepository.fetchTemplates: the deployed relation is
            // queried by home and ordered without a server-side archive filter.
            let loadedTemplates: [PhoneChoreTemplate] = try await client
                .from("chore_templates")
                .select("id,room_id,title,points_value")
                .eq("home_id", value: homeID.uuidString)
                .order("title")
                .execute()
                .value
            rooms = loadedRooms
            templates = loadedTemplates
        } catch {
            errorMessage = "We couldn't load your rooms and chores."
            #if DEBUG
            print("[Homey] LOAD PHONE CHORES: \(String(reflecting: error))")
            #endif
        }
    }
}

struct ChoreApprovalsView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Approvals",
            message: "Chore approvals will appear here.",
            symbol: "checkmark.seal"
        )
    }
}

struct ChoreRewardsView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Rewards",
            message: "Rewards will appear here.",
            symbol: "gift"
        )
    }
}

struct ChorePlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 72, height: 72)
                    .background(HomeyColors.field, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(HomeyTypography.headline)
                    .foregroundStyle(HomeyColors.text)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 28)
        }
    }
}
