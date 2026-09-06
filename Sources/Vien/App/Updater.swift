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

  /// The GitHub API, filtered to native releases: `releases/latest` would return the Electron app.
  static let repo = "L0stInFades/vien"
  static let releasesAPI = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!

  /// An explicit feed (a direct appcast.json), or nil to discover the newest `native-v*` release.
  var explicitFeed: URL? {
    if let s = ProcessInfo.processInfo.environment["VIEN_UPDATE_FEED"], let u = URL(string: s) { return u }
    if let s = UserDefaults.standard.string(forKey: "UpdateFeedURL"), let u = URL(string: s) { return u }
    return nil
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
    if let explicit = explicitFeed { return try JSONDecoder().decode(Appcast.self, from: try await get(explicit)) }
    // Discover the newest release whose tag starts with `native-v`, then read its appcast.json asset.
    struct Release: Decodable { let tag_name: String; let assets: [Asset]; let prerelease: Bool
      struct Asset: Decodable { let name: String; let browser_download_url: URL } }
    let releases = try JSONDecoder().decode([Release].self, from: try await get(Self.releasesAPI))
    guard let release = releases.first(where: { $0.tag_name.hasPrefix("native-v") }),
      let asset = release.assets.first(where: { $0.name == "appcast.json" })
    else { throw UpdateError("No native release is available yet.") }
    return try JSONDecoder().decode(Appcast.self, from: try await get(asset.browser_download_url))
  }

  /// GETs `url` and fails on any non-2xx status instead of decoding an error page.
  private func get(_ url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw UpdateError("The update server returned \(http.statusCode).")
    }
    return data
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
      var keepWork = false
      defer { if !keepWork { try? FileManager.default.removeItem(at: work) } }
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
        // Move it somewhere durable (the work dir is deleted on return) before revealing it.
        let downloads = (try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? folder
        var dest = downloads.appendingPathComponent("Vien \(appcast.version).app")
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) { dest = downloads.appendingPathComponent("Vien \(appcast.version) (\(n)).app"); n += 1 }
        if (try? FileManager.default.moveItem(at: app, to: dest)) != nil { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        throw UpdateError("Vien cannot replace itself in \(folder.path). The new version is in your Downloads folder; drag it to Applications.")
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

  /// Semantic-version order with prerelease handling: 1.0.0-beta.1 < 1.0.0, a leading `v` ignored.
  static func isNewer(_ a: String, than b: String) -> Bool { compare(a, b) > 0 }

  static func compare(_ a: String, _ b: String) -> Int {
    func split(_ s: String) -> (core: [Int], pre: [String]) {
      var v = s.trimmingCharacters(in: .whitespaces)
      if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
      let parts = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
      let core = parts[0].split(separator: ".").map { Int($0) ?? 0 }
      let pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
      return (core, pre)
    }
    let x = split(a), y = split(b)
    for i in 0..<max(x.core.count, y.core.count) {
      let p = i < x.core.count ? x.core[i] : 0, q = i < y.core.count ? y.core[i] : 0
      if p != q { return p < q ? -1 : 1 }
    }
    // A version with a prerelease suffix is older than the same core version without one.
    if x.pre.isEmpty != y.pre.isEmpty { return x.pre.isEmpty ? 1 : -1 }
    for i in 0..<max(x.pre.count, y.pre.count) {
      guard i < x.pre.count else { return -1 }
      guard i < y.pre.count else { return 1 }
      let p = x.pre[i], q = y.pre[i]
      if p != q {
        if let pi = Int(p), let qi = Int(q) { return pi < qi ? -1 : 1 }
        return p < q ? -1 : 1
      }
    }
    return 0
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

  /// A signed app only accepts updates signed by the same team. Fails closed: if the running app is
  /// signed we require a matching Team ID on the download (and reading either signature must succeed).
  /// An unsigned (ad-hoc) running app — a local dev build — skips the check so testing still works.
  static func verifySignature(of app: URL, matching running: URL) throws {
    let mine = try teamID(of: running)  // throws if the running signature cannot be validated
    guard let mine else { return }      // ad-hoc dev build: nothing to match against
    guard try teamID(of: app) == mine else { throw UpdateError("The downloaded app was signed by a different developer.") }
  }

  private func alert(_ title: String, _ info: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) { a.beginSheetModal(for: window) } else { a.runModal() }
  }
}
