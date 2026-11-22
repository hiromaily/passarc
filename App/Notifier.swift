import AppKit
@preconcurrency import UserNotifications
import os

private let log = Logger(subsystem: "local.passarc.app", category: "notification")

/// The completion notification. Clicking it reveals the results in Finder.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  private lazy var center = UNUserNotificationCenter.current()  // created lazily: it throws outside an app bundle
  private lazy var completionSound = NSSound(named: "Glass")

  func playCompletionSound() {
    completionSound?.play()
  }

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

  enum Action: String {
    case created = "Created"
    case extracted = "Extracted"
  }

  func postCompleted(_ file: URL, action: Action = .created) {
    let content = UNMutableNotificationContent()
    content.title = "\(action.rawValue) \(file.lastPathComponent)"
    content.body = file.deletingLastPathComponent().path
    content.userInfo = ["path": file.path]
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  func postArchivesCreated(_ files: [URL]) {
    guard let first = files.first else { return }
    if files.count == 1 {
      postCompleted(first)
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "Created \(files.count) archives"
    content.body = "Click to show the archives in Finder."
    content.userInfo = ["paths": files.map(\.path)]
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    let paths = info["paths"] as? [String] ?? (info["path"] as? String).map { [$0] } ?? []
    guard !paths.isEmpty else { return }
    await MainActor.run {
      NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(filePath: $0) })
    }
  }

  /// Show notifications even while the app is in front
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
