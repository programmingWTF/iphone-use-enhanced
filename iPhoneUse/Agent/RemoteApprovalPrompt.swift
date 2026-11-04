//
//  RemoteApprovalPrompt.swift
//  iPhoneUse
//
//  System notification for foreground remote-approval requests. No gateway change.
//
import Foundation
import UserNotifications

enum ApprovalPrompt {
    static weak var alignedDelegate: ApprovalPromptDelegate?
    static func requestAndReport(completion: @escaping (Bool, Error?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async { completion(granted, error) }
        }
    }
}

final class ApprovalPromptDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let id = userInfo["remote.taskID"] as? String,
           RemoteGateway.shared.pending?.id == id {
            NotificationCenter.default.post(Notification.Name("iPhoneUse.OpenApproval"), object: self, userInfo: userInfo)
        }
        completionHandler()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor final class ApprovalPromptCoordinator: ObservableObject {
    static let shared = ApprovalPromptCoordinator()
    private var done = false
    private init() {}
    func align(_ center: UNUserNotificationCenter) {
        if !done {
            center.delegate = ApprovalPromptDelegate()
            done = true
        }
    }
}

extension RemoteGateway {
    private func notifyRemoteApproval(_ request: RemoteRequest) {
        guard approvalAlertEnabled, pending?.id == request.id else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                DispatchQueue.main.async { self.notificationStatus = t("系统通知权限未授予——请在 iOS 设置 > 通知中开启") }
                return
            }
            DispatchQueue.main.async {
                self.notificationStatus = t("系统通知已开启")
                let content = UNMutableNotificationContent()
                let preview = String(request.prompt.prefix(160))
                content.title = t("远程 Agent 请求")
                content.body = "\(request.agent): \(preview)"
                content.sound = .default
                content.interruptionLevel = .active
                content.userInfo = ["remote.taskID": request.id]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request2 = UNNotificationRequest(identifier: "remote.approval.\(request.id)", content: content, trigger: trigger)
                center.add(request2); center.removePendingNotificationRequests(withIdentifiers: ["remote.approval.\(request.id)"])
                // Fire immediately instead of 1s delay (more timely for 120s expiry):
                if pending?.id == request.id { center.add(request2) }
            }
        }
    }
    private func clearApprovalNotification(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["remote.approval.\(id)"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["remote.approval.\(id)"])
    }
}
