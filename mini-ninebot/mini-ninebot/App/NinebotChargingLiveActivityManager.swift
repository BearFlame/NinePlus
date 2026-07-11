import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum NinebotChargingLiveActivityManager {
    static func startRemoteTokenObservation() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task { @MainActor in
            NinebotChargingLiveActivityTokenObserver.shared.start()
        }
        #endif
    }

    static func sync(with dashboard: NinebotDashboard) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            await NinebotChargingActivityController.sync(with: dashboard)
        }
        #endif
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private enum NinebotChargingActivityController {
    static func sync(with dashboard: NinebotDashboard) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        guard let snapshot = dashboard.primaryVehicle,
              snapshot.state.isCharging == true,
              !snapshot.state.isFullyCharged,
              let battery = snapshot.state.battery else {
            await endAll()
            return
        }

        let attributes = NinebotChargingActivityAttributes(
            vehicleSN: snapshot.vehicle.sn,
            vehicleName: snapshot.vehicle.name,
            vehicleModel: snapshot.vehicle.model
        )
        let state = NinebotChargingActivityAttributes.ContentState(
            battery: battery,
            estimatedRange: snapshot.state.localEstimatedMileage ?? snapshot.state.endurance ?? snapshot.state.aiEstimatedMileage,
            estimatedFullAt: estimatedFullAt(for: snapshot.state),
            chargingPower: snapshot.state.chargingPower,
            batteryTemperature: snapshot.state.batteryTemperature,
            batteryVoltage: snapshot.state.batteryVoltage,
            chargingSpeed: snapshot.state.estimatedChargingSpeedKmh,
            updatedAt: snapshot.state.updatedAt
        )
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(for: state)
        )

        let activities = Activity<NinebotChargingActivityAttributes>.activities
        let matchingActivity = activities.first { $0.attributes.vehicleSN == snapshot.vehicle.sn }
        NinebotSharedStore().pruneChargingLiveActivityPushTokens(activeActivityIDs: Set(activities.map(\.id)))
        await MainActor.run {
            for activity in activities {
                NinebotChargingLiveActivityTokenObserver.shared.observeActivity(activity)
            }
        }

        for activity in activities where activity.id != matchingActivity?.id {
            await activity.end(content, dismissalPolicy: .immediate)
            NinebotSharedStore().removeChargingLiveActivityPushToken(activityID: activity.id)
        }

        if let matchingActivity {
            await matchingActivity.update(content)
        } else {
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
                await MainActor.run {
                    NinebotChargingLiveActivityTokenObserver.shared.observeActivity(activity)
                }
            } catch {
                #if DEBUG
                print("Failed to start NineBot charging Live Activity: \(error)")
                #endif
            }
        }
    }

    private static func endAll() async {
        for activity in Activity<NinebotChargingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        NinebotSharedStore().removeAllChargingLiveActivityPushTokens()
    }

    private static func estimatedFullAt(for state: NinebotVehicleState) -> Date? {
        guard let minutes = state.estimatedFullChargeMinutes, minutes > 0 else { return nil }
        return Date().addingTimeInterval(minutes * 60)
    }

    private static func staleDate(for state: NinebotChargingActivityAttributes.ContentState) -> Date {
        if let estimatedFullAt = state.estimatedFullAt, estimatedFullAt > Date() {
            return estimatedFullAt.addingTimeInterval(5 * 60)
        }
        return Date().addingTimeInterval(60 * 60)
    }

}

@available(iOS 16.1, *)
@MainActor
private final class NinebotChargingLiveActivityTokenObserver {
    static let shared = NinebotChargingLiveActivityTokenObserver()

    private let store = NinebotSharedStore()
    private var pushToStartTask: Task<Void, Never>?
    private var activityUpdatesTask: Task<Void, Never>?
    private var activityTokenTasks: [String: Task<Void, Never>] = [:]

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        observeExistingActivities()
        observeActivityUpdates()
        observePushToStartToken()
    }

    func observeActivity(_ activity: Activity<NinebotChargingActivityAttributes>) {
        if let token = activity.pushToken {
            registerActivityPushToken(token, activity: activity)
        }

        guard activityTokenTasks[activity.id] == nil else { return }
        activityTokenTasks[activity.id] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                self?.registerActivityPushToken(tokenData, activity: activity)
            }
        }
    }

    private func observeExistingActivities() {
        let activities = Activity<NinebotChargingActivityAttributes>.activities
        store.pruneChargingLiveActivityPushTokens(activeActivityIDs: Set(activities.map(\.id)))
        for activity in activities {
            observeActivity(activity)
        }
    }

    private func observeActivityUpdates() {
        guard activityUpdatesTask == nil else { return }
        activityUpdatesTask = Task { [weak self] in
            for await activity in Activity<NinebotChargingActivityAttributes>.activityUpdates {
                self?.observeActivity(activity)
            }
        }
    }

    private func observePushToStartToken() {
        guard #available(iOS 17.2, *) else { return }

        if let token = Activity<NinebotChargingActivityAttributes>.pushToStartToken {
            registerPushToStartToken(token)
        }

        guard pushToStartTask == nil else { return }
        pushToStartTask = Task { [weak self] in
            for await tokenData in Activity<NinebotChargingActivityAttributes>.pushToStartTokenUpdates {
                self?.registerPushToStartToken(tokenData)
            }
        }
    }

    private func registerPushToStartToken(_ data: Data) {
        let token = data.hexString
        guard !token.isEmpty else { return }
        store.saveChargingLiveActivityPushToStartToken(token)
        Task {
            try? await NinebotPushManager.shared.registerStoredLiveActivityTokensWithServer()
        }
    }

    private func registerActivityPushToken(_ data: Data, activity: Activity<NinebotChargingActivityAttributes>) {
        let token = data.hexString
        guard !token.isEmpty else { return }
        store.saveChargingLiveActivityPushToken(token, activityID: activity.id, vehicleSN: activity.attributes.vehicleSN)
        Task {
            try? await NinebotPushManager.shared.registerLiveActivityPushTokenWithServer(
                token: token,
                activityID: activity.id,
                vehicleSN: activity.attributes.vehicleSN
            )
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#endif
