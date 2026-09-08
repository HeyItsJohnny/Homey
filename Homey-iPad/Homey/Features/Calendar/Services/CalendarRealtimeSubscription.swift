import Foundation
import Supabase

@MainActor
final class CalendarRealtimeSubscription {
    private let channel: RealtimeChannelV2
    private var listenerTasks: [Task<Void, Never>]

    init(channel: RealtimeChannelV2, listenerTasks: [Task<Void, Never>]) {
        self.channel = channel
        self.listenerTasks = listenerTasks
    }

    func cancel() async {
        listenerTasks.forEach { $0.cancel() }
        listenerTasks.removeAll()

        await channel.unsubscribe()
    }
}
