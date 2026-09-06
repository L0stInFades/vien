import AppKit
import CryptoKit
import Security

/// In-app updates from GitHub Releases, with nothing but Apple frameworks: fetch the appcast,
/// compare versions, download the archive, check its SHA-256, unpack, verify the code signature
/// (same Team ID as the running app), swap the bundle in place and relaunch.
final class Updater {
  static let shared = Updater()

  struct Appcast: Decodable {
    var version: String
    var build: String?
    var minimumSystemVersion: String?
    var url: URL
    var sha256: String
    var notes: String?
  }

  struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
  }

  /// `releases/latest/download/<asset>` always points at the newest release's appcast.
  static let defaultFeed = URL(string: "https://github.com/L0stInFades/vien/releases/latest/download/appcast.json")!

  var feed: URL {
    if let s = ProcessInfo.processInfo.environment["VIEN_UPDATE_FEED"], let u = URL(string: s) { return u }
    if let s = UserDefaults.standard.string(forKey: "UpdateFeedURL"), let u = URL(string: s) { return u }
    return Self.defaultFeed
  }

  var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
  private var busy = false

  /// Quiet daily check, only for a real app bundle with the preference on.
  func checkAutomatically() {
    guard Preferences.shared.automaticUpdates, Bundle.main.bundleIdentifier != nil else { return }
    guard Date().timeIntervalSince1970 - Preferences.shared.lastUpdateCheck > 86_400 else { return }
    Task { await check(userInitiated: false) }
  }

  func check(userInitiated: Bool) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let appcast = try await fetch()
      Preferences.shared.lastUpdateCheck = Date().timeIntervalSince1970
      guard Self.isNewer(appcast.version, than: currentVersion) else {
        if userInitiated { alert("You’re up to date.", "Vien \(currentVersion) is the newest version.") }
        return
      }
      if !userInitiated, Preferences.shared.skippedUpdateVersion == appcast.version { return }
      if let min = appcast.minimumSystemVersion, !Self.systemSatisfies(min) {
        if userInitiated { alert("Vien \(appcast.version) needs macOS \(min).", "This Mac is running an older version of macOS.") }
        return
      }
      offer(appcast)
    } catch {
      if userInitiated { alert("Could not check for updates.", error.localizedDescription) }
    }
  }

  /// Fetches and installs without asking (automation and tests).
  func checkAndInstall() async {
    do { await install(try await fetch()) } catch { alert("Could not check for updates.", error.localizedDescription) }
  }

  private func fetch() async throws -> Appcast {
    let (data, _) = try await URLSession.shared.data(from: feed)
    return try JSONDecoder().decode(Appcast.self, from: data)
  }

  private func offer(_ appcast: Appcast) {
    let alert = NSAlert()
    alert.messageText = "Vien \(appcast.version) is available"
    var info = "You have \(currentVersion)."
    if let notes = appcast.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { info += "\n\n" + notes.prefix(1500) }
    alert.informativeText = info
    alert.addButton(withTitle: "Download and Install")
    alert.addButton(withTitle: "Later")
    alert.addButton(withTitle: "Skip This Version")
    let handle: (NSApplication.ModalResponse) -> Void = { response in
      switch response {
      case .alertFirstButtonReturn: Task { await Updater.shared.install(appcast) }
      case .alertThirdButtonReturn: Preferences.shared.skippedUpdateVersion = appcast.version
      default: break
      }
    }
    if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
      alert.beginSheetModal(for: window, completionHandler: handle)
    } else {
      handle(alert.runModal())
    }
  }

  func install(_ appcast: Appcast) async {
    do {
      let current = Bundle.main.bundleURL
      guard Bundle.main.bundleIdentifier != nil else { throw UpdateError("Updates apply to the installed app, not to a development build.") }
      let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
      defer { try? FileManager.default.removeItem(at: work) }
      let (downloaded, _) = try await URLSession.shared.download(from: appcast.url)
      let archive = work.appendingPathComponent("Vien.zip")
      try FileManager.default.moveItem(at: downloaded, to: archive)
      guard try Self.sha256(of: archive) == appcast.sha256.lowercased() else { throw UpdateError("The download did not match its checksum.") }
      let unpacked = work.appendingPathComponent("unpacked")
      try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
      try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
      guard let app = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
        throw UpdateError("The archive does not contain an app.")
      }
      try Self.verifySignature(of: app, matching: current)
      let folder = current.deletingLastPathComponent()
      guard FileManager.default.isWritableFile(atPath: folder.path) else {
        NSWorkspace.shared.activateFileViewerSelecting([app])
        throw UpdateError("Vien cannot replace itself in \(folder.path). The new version is selected in the Finder; drag it to Applications.")
      }
      // Move the running bundle aside (the process keeps working), put the new one in its place.
      if (try? FileManager.default.trashItem(at: current, resultingItemURL: nil)) == nil {
        try FileManager.default.moveItem(at: current, to: folder.appendingPathComponent("Vien (old).app"))
      }
      try FileManager.default.moveItem(at: app, to: current)
      relaunch(current)
    } catch {
      alert("Update failed.", error.localizedDescription)
    }
  }

  /// Quits, then a detached shell opens the new bundle once this process is gone.
  private func relaunch(_ url: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(url.path)\""]
    try? p.run()
    NSApp.terminate(nil)
  }

  // MARK: - Checks

  static func isNewer(_ a: String, than b: String) -> Bool {
    func parts(_ s: String) -> [Int] { s.split(separator: "-").first?.split(separator: ".").map { Int($0) ?? 0 } ?? [] }
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
      let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
      if p != q { return p > q }
    }
    return false
  }

  static func systemSatisfies(_ minimum: String) -> Bool {
    let v = minimum.split(separator: ".").map { Int($0) ?? 0 }
    guard !v.isEmpty else { return true }
    return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: v[0], minorVersion: v.count > 1 ? v[1] : 0, patchVersion: v.count > 2 ? v[2] : 0))
  }

  static func sha256(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
  }

  static func run(_ tool: String, _ arguments: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = arguments
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(p.terminationStatus)).") }
  }

  /// The signing Team ID after a strict validity check (nil for an ad-hoc signature).
  static func teamID(of url: URL) throws -> String? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError("Cannot read the app’s code signature.") }
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw UpdateError("The downloaded app’s code signature is not valid.") }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess, let dict = info as? [String: Any] else { return nil }
    return dict[kSecCodeInfoTeamIdentifier as String] as? String
  }

  /// A signed app only accepts updates signed by the same team.
  static func verifySignature(of app: URL, matching running: URL) throws {
    let new = try teamID(of: app)
    if let mine = try? teamID(of: running), new != mine { throw UpdateError("The downloaded app was signed by a different developer.") }
  }

  private func alert(_ title: String, _ info: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) { a.beginSheetModal(for: window) } else { a.runModal() }
  }
}
