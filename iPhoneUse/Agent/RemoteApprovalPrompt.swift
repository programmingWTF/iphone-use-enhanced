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
        if let id = userInfo["remote.taskID"] as? String {
            Task { @MainActor in
                if RemoteGateway.shared.pending?.id == id {
                    NotificationCenter.default.post(name: Notification.Name("iPhoneUse.OpenApproval"), object: RemoteGateway.shared, userInfo: userInfo)
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension RemoteGateway {
    func notifyRemoteApproval(_ request: RemoteRequest) {
        guard approvalAlertEnabled, pending?.id == request.id else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard self.pending?.id == request.id else { return }
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    self.notificationStatus = t("系统通知权限未授予——请在 iOS 设置 > 通知中开启")
                    return
                }
                self.notificationStatus = t("系统通知已开启")
                let content = UNMutableNotificationContent()
                let preview = String(request.prompt.prefix(160))
                content.title = t("远程 Agent 请求")
                content.body = "\(request.agent): \(preview)"
                content.sound = .default
                content.interruptionLevel = .active
                content.userInfo = ["remote.taskID": request.id]
                center.add(UNNotificationRequest(identifier: "remote.approval.\(request.id)", content: content, trigger: nil))
            }
        }
    }

    func clearApprovalNotification(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["remote.approval.\(id)"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["remote.approval.\(id)"])
    }
}
