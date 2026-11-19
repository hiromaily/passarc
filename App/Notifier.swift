import AppKit
@preconcurrency import UserNotifications
import os

private let log = Logger(subsystem: "local.passarc.app", category: "notification")

/// The completion notification. Clicking it reveals the file in Finder.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  private lazy var center = UNUserNotificationCenter.current()  // created lazily: it throws outside an app bundle

  func start() {
    center.delegate = self
    // A completion closure here is inferred @MainActor but called on a background queue,
    // which crashes under Swift 6. Use the async API.
    let center = self.center
    Task {
      do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        log.notice("authorization granted=\(granted)")
      } catch {
        log.error("authorization failed: \(String(describing: error), privacy: .public)")
      }
      let settings = await center.notificationSettings()
      log.notice("authorizationStatus=\(settings.authorizationStatus.rawValue) alertStyle=\(settings.alertStyle.rawValue)")
    }
  }

  func postCompleted(_ file: URL) {
    let content = UNMutableNotificationContent()
    content.title = "Created \(file.lastPathComponent)"
    content.body = file.deletingLastPathComponent().path
    content.userInfo = ["path": file.path]
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
    await MainActor.run {
      NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }
  }

  /// Show notifications even while the app is in front
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
