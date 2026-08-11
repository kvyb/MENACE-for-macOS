import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum BuilderFailure: LocalizedError, Equatable {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}

public struct LockedDependency: Equatable, Sendable {
    public let name: String
    public let fileName: String
    public let version: String
    public let url: URL
    public let sha256: String

    public init(name: String, fileName: String, version: String, url: URL, sha256: String) {
        self.name = name
        self.fileName = fileName
        self.version = version
        self.url = url
        self.sha256 = sha256
    }
}

public enum LockedDependencies {
    public static let template = LockedDependency(
        name: "Sikarugir wrapper template",
        fileName: "Template-1.0.11.tar.xz",
        version: "1.0.11",
        url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz")!,
        sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
    )

    public static let engine = LockedDependency(
        name: "Sikarugir Wine engine",
        fileName: "WS12WineSikarugir10.0_6.tar.xz",
        version: "WS12WineSikarugir10.0_6",
        url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz")!,
        sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2"
    )

    public static let sevenZip = LockedDependency(
        name: "7-Zip archive helper",
        fileName: "7z2602-mac.tar.xz",
        version: "26.02",
        url: URL(string: "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-mac.tar.xz")!,
        sha256: "1cf6760579502f87e591ff5c73a005ec50b3e4d6f507e8b038382d563c3175b9"
    )

    public static let steamInstaller = LockedDependency(
        name: "Valve Steam installer",
        fileName: "SteamSetup.exe",
        version: "2026-08-05",
        url: URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!,
        sha256: "7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb"
    )

    public static let artwork = LockedDependency(
        name: "Official MENACE Steam library artwork",
        fileName: "MENACE-library-600x900.jpg",
        version: "2026-08-09",
        url: URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/2432860/library_600x900_2x.jpg")!,
        sha256: "5c435807d61ca26252d016d7f9afdc1099596a85e13bd705bc7a33bcab6fd235"
    )

    public static let all = [template, engine, sevenZip, steamInstaller, artwork]
}

public enum BuildSource: Equatable, Sendable {
    case gameFiles(URL)
    case steam
}

public struct BuildOptions: Sendable {
    public var source: BuildSource
    public var outputDirectory: URL
    public var cacheDirectory: URL
    public var dependencyDirectory: URL?
    public var createDMG: Bool
    public var keepWorkDirectory: Bool
    public var force: Bool
    public var offline: Bool
    public var verbose: Bool

    public init(
        source: BuildSource,
        outputDirectory: URL,
        cacheDirectory: URL,
        dependencyDirectory: URL? = nil,
        createDMG: Bool = true,
        keepWorkDirectory: Bool = false,
        force: Bool = false,
        offline: Bool = false,
        verbose: Bool = false
    ) {
        self.source = source
        self.outputDirectory = outputDirectory
        self.cacheDirectory = cacheDirectory
        self.dependencyDirectory = dependencyDirectory
        self.createDMG = createDMG
        self.keepWorkDirectory = keepWorkDirectory
        self.force = force
        self.offline = offline
        self.verbose = verbose
    }
}

public struct BuildResult: Sendable {
    public let app: URL
    public let dmg: URL?
    public let report: URL
}

public struct CommandResult: Sendable {
    public let output: String
    public let status: Int32
}

public struct ProcessRunner: Sendable {
    public let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    @discardableResult
    public func run(
        _ executable: String,
        _ arguments: [String] = [],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        if verbose {
            print("  $ \(([executable] + arguments).map(shellQuoted).joined(separator: " "))")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        do {
            try process.run()
        } catch {
            throw BuilderFailure.message("Could not run \(executable): \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BuilderFailure.message(
                "Command failed (\(process.terminationStatus)): \(executable)" +
                    (detail.isEmpty ? "" : "\n\(detail)")
            )
        }

        return CommandResult(output: output, status: process.terminationStatus)
    }
}

private func shellQuoted(_ value: String) -> String {
    if value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:".contains($0) }) {
        return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

public enum HostChecks {
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
        #endif
    }

    public static var hasRosetta: Bool {
        guard isAppleSilicon else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum WineInput {
    static let compatibilityRegistryArguments = [
        "reg", "add", #"HKCU\Software\Wine\AppDefaults\Menace.exe\Mac Driver"#,
        "/v", "UsePreciseScrolling", "/t", "REG_SZ", "/d", "N", "/f"
    ]
}

public enum GameLayout {
    private static let requiredNames = ["menace.exe", "menace_data", "unityplayer.dll", "gameassembly.dll"]

    public static func locateRoot(in searchRoot: URL) throws -> URL {
        let root = searchRoot.standardizedFileURL
        var candidates: [URL] = []

        if isValidRoot(root) {
            candidates.append(root)
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let item as URL in enumerator {
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isDirectory == true else { continue }
                if isValidRoot(item) {
                    candidates.append(item)
                    enumerator.skipDescendants()
                }
            }
        }

        let unique = Array(Set(candidates.map(\.standardizedFileURL.path))).sorted()
        guard unique.count == 1 else {
            if unique.isEmpty {
                throw BuilderFailure.message(
                    "No MENACE game folder found. Expected Menace.exe, Menace_Data, UnityPlayer.dll, and GameAssembly.dll together."
                )
            }
            throw BuilderFailure.message("More than one MENACE game folder was found. Please select the correct folder directly.")
        }
        return URL(fileURLWithPath: unique[0], isDirectory: true)
    }

    public static func validateNoSymlinks(in root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: Set(keys)).isSymbolicLink == true {
                throw BuilderFailure.message("The game copy contains a symbolic link and was rejected for safety: \(item.lastPathComponent)")
            }
        }
    }

    public static func validateArchiveEntry(_ rawPath: String) throws {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        let lower = path.lowercased()
        let components = path.split(separator: "/", omittingEmptySubsequences: false)

        if path.hasPrefix("/") || path.hasPrefix("~") || lower.hasPrefix("file:") {
            throw BuilderFailure.message("Archive contains an unsafe absolute path: \(rawPath)")
        }
        if path.range(of: "^[A-Za-z]:", options: .regularExpression) != nil {
            throw BuilderFailure.message("Archive contains an unsafe Windows drive path: \(rawPath)")
        }
        if components.contains("..") {
            throw BuilderFailure.message("Archive contains an unsafe parent path: \(rawPath)")
        }
    }

    public static func validateSevenZipListing(_ listing: String) throws {
        var readingEntries = false
        for line in listing.split(separator: "\n") {
            if line == "----------" {
                readingEntries = true
                continue
            }
            if readingEntries, line == "Encrypted = +" {
                throw BuilderFailure.message("Password-protected archives are not supported. Extract it first, then select the game folder.")
            }
            guard readingEntries, line.hasPrefix("Path = ") else { continue }
            try validateArchiveEntry(String(line.dropFirst("Path = ".count)))
        }
        guard readingEntries else {
            throw BuilderFailure.message("Could not read the archive file list.")
        }
    }

    public static func detectedVersion(from source: URL) -> String? {
        let name = source.deletingPathExtension().lastPathComponent
        let pattern = #"(?i)(?:^|[^0-9])v?(\d+\.\d+(?:\.\d+)?)(?:[^0-9]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return String(name[range])
    }

    private static func isValidRoot(_ directory: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        let lowerNames = Set(names.map { $0.lowercased() })
        return requiredNames.allSatisfy(lowerNames.contains)
    }
}

public final class MENACEBuilder {
    public static let version = "0.2.2"

    private let fileManager = FileManager.default
    private let options: BuildOptions
    private let runner: ProcessRunner

    public init(options: BuildOptions) {
        self.options = options
        runner = ProcessRunner(verbose: options.verbose)
    }

    public func build() throws -> BuildResult {
        try preflight()
        try fileManager.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: options.cacheDirectory, withIntermediateDirectories: true)

        let work = fileManager.temporaryDirectory
            .appendingPathComponent("menace-macos-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        if options.verbose { print("  Work directory: \(work.path)") }
        defer {
            if options.keepWorkDirectory {
                print("  Kept work directory: \(work.path)")
            } else {
                try? fileManager.removeItem(at: work)
            }
        }

        let dependencyStore = DependencyStore(
            cache: options.cacheDirectory,
            overrideDirectory: options.dependencyDirectory,
            offline: options.offline,
            runner: runner
        )
        let gameRoot: URL?
        let gameVersion: String?
        switch options.source {
        case let .gameFiles(source):
            print("[1/7] Reading your game copy")
            let root = try prepareGameSource(source, in: work, dependencyStore: dependencyStore)
            try GameLayout.validateNoSymlinks(in: root)
            gameRoot = root
            gameVersion = GameLayout.detectedVersion(from: source)
        case .steam:
            print("[1/7] Preparing the Steam edition")
            gameRoot = nil
            gameVersion = nil
        }

        print("[2/7] Getting verified macOS runtime")
        let templateArchive = try dependencyStore.file(for: LockedDependencies.template)
        let engineArchive = try dependencyStore.file(for: LockedDependencies.engine)
        let artwork = try dependencyStore.file(for: LockedDependencies.artwork)

        print("[3/7] Assembling MENACE.app")
        let app = try assembleApp(
            work: work,
            gameVersion: gameVersion,
            templateArchive: templateArchive,
            engineArchive: engineArchive,
            artwork: artwork
        )

        print("[4/7] Initializing private Wine data")
        try initializePrefix(in: app)

        print("[5/7] Installing DXMT and locking file access")
        try installDXMT(in: app)
        try hardenPrefix(in: app)
        if let gameRoot {
            try copyGame(from: gameRoot, into: app)
        }

        print("[6/7] Signing and verifying the app")
        try signAndVerify(app)

        print("[7/7] Writing the app and DMG")
        let result = try publish(app: app, gameVersion: gameVersion, work: work)
        print("\nBuilt successfully:")
        print("  App: \(result.app.path)")
        if let dmg = result.dmg { print("  DMG: \(dmg.path)") }
        print("  Report: \(result.report.path)")
        return result
    }

    private func preflight() throws {
        guard HostChecks.isAppleSilicon else {
            throw BuilderFailure.message("This first release supports Apple Silicon Macs only.")
        }
        guard HostChecks.hasRosetta else {
            throw BuilderFailure.message(
                "Rosetta 2 is required. Install it with:\n/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
            )
        }

        if case let .gameFiles(source) = options.source {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
                throw BuilderFailure.message("Game copy not found: \(source.path)")
            }
        }

        let parent = options.outputDirectory.deletingLastPathComponent()
        let capacity = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let requiredCapacity: Int64 = switch options.source {
        case .gameFiles: options.createDMG ? 50_000_000_000 : 40_000_000_000
        case .steam: 10_000_000_000
        }
        if let capacity, capacity > 0, capacity < requiredCapacity {
            let requiredGB = requiredCapacity / 1_000_000_000
            throw BuilderFailure.message("At least \(requiredGB) GB of free disk space is required for this build.")
        }
    }

    private func prepareGameSource(_ source: URL, in work: URL, dependencyStore: DependencyStore) throws -> URL {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return try GameLayout.locateRoot(in: source)
        }

        if source.pathExtension.lowercased() == "exe" {
            guard source.lastPathComponent.lowercased() == "menace.exe" else {
                throw BuilderFailure.message("Select Menace.exe itself, not a Windows installer.")
            }
            return try GameLayout.locateRoot(in: source.deletingLastPathComponent())
        }

        let supported = ["rar", "7z", "zip", "tar", "xz"]
        guard supported.contains(source.pathExtension.lowercased()) else {
            throw BuilderFailure.message("Unsupported input. Use a RAR, 7Z, ZIP, extracted folder, or Menace.exe.")
        }

        let sevenZip = try dependencyStore.sevenZipExecutable()
        let listing = try runner.run(sevenZip.path, ["l", "-slt", source.path]).output
        try GameLayout.validateSevenZipListing(listing)

        let extraction = work.appendingPathComponent("game", isDirectory: true)
        try fileManager.createDirectory(at: extraction, withIntermediateDirectories: true)
        try runner.run(sevenZip.path, ["x", "-y", "-bb0", "-o\(extraction.path)", source.path])
        return try GameLayout.locateRoot(in: extraction)
    }

    private func assembleApp(
        work: URL,
        gameVersion: String?,
        templateArchive: URL,
        engineArchive: URL,
        artwork: URL
    ) throws -> URL {
        let templateRoot = work.appendingPathComponent("template", isDirectory: true)
        let engineRoot = work.appendingPathComponent("engine", isDirectory: true)
        try fileManager.createDirectory(at: templateRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: engineRoot, withIntermediateDirectories: true)
        try runner.run("/usr/bin/tar", ["-xf", templateArchive.path, "-C", templateRoot.path])
        try runner.run("/usr/bin/tar", ["-xf", engineArchive.path, "-C", engineRoot.path])

        let originalApp = templateRoot.appendingPathComponent("Template-1.0.11.app", isDirectory: true)
        let app = work.appendingPathComponent("MENACE.app", isDirectory: true)
        guard fileManager.fileExists(atPath: originalApp.path) else {
            throw BuilderFailure.message("Verified template did not contain Template-1.0.11.app.")
        }
        try fileManager.moveItem(at: originalApp, to: app)

        let engine = engineRoot.appendingPathComponent("wswine.bundle", isDirectory: true)
        let installedEngine = app.appendingPathComponent("Contents/SharedSupport/wswine", isDirectory: true)
        guard fileManager.fileExists(atPath: engine.path) else {
            throw BuilderFailure.message("Verified engine did not contain wswine.bundle.")
        }
        try runner.run("/usr/bin/ditto", [engine.path, installedEngine.path])

        try configureInfoPlist(in: app, gameVersion: gameVersion)
        try installLauncher(in: app)
        try AppIcon.install(
            artwork: artwork,
            in: app,
            runner: runner,
            rendererExecutable: Bundle.main.executableURL
        )
        return app
    }

    func configureInfoPlist(in app: URL, gameVersion: String?) throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BuilderFailure.message("The wrapper Info.plist is invalid.")
        }

        plist["CFBundleExecutable"] = "launcher"
        plist["CFBundleIdentifier"] = switch options.source {
        case .gameFiles: "io.github.kvyb.MENACEForMacOS"
        case .steam: "io.github.kvyb.MENACEForMacOS.Steam"
        }
        plist["CFBundleName"] = "MENACE"
        plist["CFBundleDisplayName"] = "MENACE"
        plist["CFBundleIconFile"] = "MENACE.icns"
        plist["CFBundleShortVersionString"] = gameVersion ?? Self.version
        plist["CFBundleVersion"] = "1"
        plist["LSMinimumSystemVersion"] = "13.0"
        switch options.source {
        case .gameFiles:
            plist["Program Name and Path"] = "/MENACE/Menace.exe"
        case .steam:
            plist["Program Name and Path"] = "/Program Files (x86)/Steam/steam.exe"
        }
        plist["DXMT"] = 1
        plist["DXVK"] = 0
        plist["D3DMETAL"] = 0
        plist["MOLTENVKCX"] = 0
        plist["Symlinks In User Folder"] = 0
        plist["WINEDEBUG"] = "-all"

        let removedKeys = [
            "NSBGOnly", "LSBackgroundOnly", "LSUIElement",
            "NSHighResolutionCapable",
            "Associations", "CFBundleDocumentTypes", "CLI Custom Commands",
            "NSAppTransportSecurity", "NSMainNibFile", "NSPrincipalClass",
            "NSBluetoothAlwaysUsageDescription", "NSBluetoothPeripheralUsageDescription",
            "NSCameraUsageDescription", "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
            "NSMicrophoneUsageDescription", "NSNetworkVolumesUsageDescription",
            "NSRemovableVolumesUsageDescription", "Symlink Desktop", "Symlink Downloads",
            "Symlink My Documents", "Symlink My Music", "Symlink My Pictures",
            "Symlink My Videos", "Symlink Templates"
        ]
        for key in removedKeys { plist.removeValue(forKey: key) }

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: plistURL, options: .atomic)
    }

    private func installLauncher(in app: URL) throws {
        let launcher = app.appendingPathComponent("Contents/MacOS/launcher")
        if fileManager.fileExists(atPath: launcher.path) || (try? launcher.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try fileManager.removeItem(at: launcher)
        }
        try Launcher.script(for: options.source).write(to: launcher, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }

    private func initializePrefix(in app: URL) throws {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let prefix = contents.appendingPathComponent("SharedSupport/prefix", isDirectory: true)
        try fileManager.createDirectory(at: prefix, withIntermediateDirectories: true)
        let wine = contents.appendingPathComponent("SharedSupport/wswine/bin/wine")
        let wineserver = contents.appendingPathComponent("SharedSupport/wswine/bin/wineserver")
        let environment = wineEnvironment(contents: contents)
        try runner.run(wine.path, ["wineboot", "-u"], environment: environment)
        try runner.run(wine.path, WineInput.compatibilityRegistryArguments, environment: environment)
        try runner.run(wineserver.path, ["-w"], environment: environment)
    }

    private func installDXMT(in app: URL) throws {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let source = contents.appendingPathComponent("Frameworks/renderer/dxmt/wine", isDirectory: true)
        let wineLibrary = contents.appendingPathComponent("SharedSupport/wswine/lib/wine", isDirectory: true)
        let system32 = contents.appendingPathComponent("SharedSupport/prefix/drive_c/windows/system32", isDirectory: true)
        let syswow64 = contents.appendingPathComponent("SharedSupport/prefix/drive_c/windows/syswow64", isDirectory: true)

        guard fileManager.fileExists(atPath: source.appendingPathComponent("x86_64-unix/winemetal.so").path) else {
            throw BuilderFailure.message("The wrapper's DXMT payload is incomplete.")
        }
        try overlay(source: source, destination: wineLibrary)
        try copyDLLs(from: source.appendingPathComponent("x86_64-windows"), to: system32)
        try copyDLLs(from: source.appendingPathComponent("i386-windows"), to: syswow64)
    }

    private func hardenPrefix(in app: URL) throws {
        let prefix = app.appendingPathComponent("Contents/SharedSupport/prefix", isDirectory: true)
        let dosDevices = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try fileManager.createDirectory(at: dosDevices, withIntermediateDirectories: true)

        for item in try fileManager.contentsOfDirectory(at: dosDevices, includingPropertiesForKeys: nil) {
            if item.lastPathComponent.lowercased() != "c:" {
                try fileManager.removeItem(at: item)
            }
        }

        let cDrive = dosDevices.appendingPathComponent("c:")
        if fileManager.fileExists(atPath: cDrive.path) || (try? cDrive.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try fileManager.removeItem(at: cDrive)
        }
        try fileManager.createSymbolicLink(atPath: cDrive.path, withDestinationPath: "../drive_c")

        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: users,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                enumerator.skipDescendants()
                try fileManager.removeItem(at: item)
                try fileManager.createDirectory(at: item, withIntermediateDirectories: true)
            }
        }
    }

    private func copyGame(from gameRoot: URL, into app: URL) throws {
        let destination = app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/MENACE", isDirectory: true)
        try runner.run("/usr/bin/ditto", [gameRoot.path, destination.path])
    }

    private func signAndVerify(_ app: URL) throws {
        let signature = app.appendingPathComponent("Contents/_CodeSignature")
        if fileManager.fileExists(atPath: signature.path) {
            try fileManager.removeItem(at: signature)
        }
        try runner.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
        try runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])

        let plistData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        guard plist?["NSBGOnly"] == nil else {
            throw BuilderFailure.message("Verification failed: NSBGOnly is still present.")
        }
        guard fileManager.fileExists(atPath: app.appendingPathComponent("Contents/SharedSupport/wswine/lib/wine/x86_64-unix/winemetal.so").path) else {
            throw BuilderFailure.message("Verification failed: DXMT is missing.")
        }
        if case .gameFiles = options.source {
            let game = app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/MENACE", isDirectory: true)
            guard fileManager.fileExists(atPath: game.appendingPathComponent("Menace.exe").path),
                  fileManager.fileExists(atPath: game.appendingPathComponent("Menace_Data", isDirectory: true).path),
                  fileManager.fileExists(atPath: game.appendingPathComponent("UnityPlayer.dll").path),
                  fileManager.fileExists(atPath: game.appendingPathComponent("GameAssembly.dll").path)
            else {
                throw BuilderFailure.message("Verification failed: the MENACE game files are incomplete.")
            }
        }
    }

    private func publish(app: URL, gameVersion: String?, work: URL) throws -> BuildResult {
        let outputApp = options.outputDirectory.appendingPathComponent("MENACE.app", isDirectory: true)
        let dmgName: String
        if case .steam = options.source {
            dmgName = "MENACE-Steam-macOS.dmg"
        } else {
            dmgName = gameVersion.map { "MENACE-macOS-v\($0).dmg" } ?? "MENACE-macOS.dmg"
        }
        let outputDMG = options.outputDirectory.appendingPathComponent(dmgName)
        let reportURL = options.outputDirectory.appendingPathComponent("BUILD-REPORT.txt")

        try prepareOutput(outputApp)
        if options.createDMG { try prepareOutput(outputDMG) }
        if fileManager.fileExists(atPath: reportURL.path), !options.force {
            throw BuilderFailure.message("Output already exists: \(reportURL.path). Use --force to replace it.")
        }
        try? fileManager.removeItem(at: reportURL)

        try runner.run("/usr/bin/ditto", [app.path, outputApp.path])
        try fileManager.removeItem(at: app)
        var report = buildReport(gameVersion: gameVersion, dmgSHA: nil)
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        var dmg: URL?
        if options.createDMG {
            let dmgRoot = work.appendingPathComponent("dmg", isDirectory: true)
            try fileManager.createDirectory(at: dmgRoot, withIntermediateDirectories: true)
            try stageForDMG(outputApp, at: dmgRoot.appendingPathComponent("MENACE.app"))
            try DmgReadme.text(for: options.source)
                .write(to: dmgRoot.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try report.write(to: dmgRoot.appendingPathComponent("BUILD-REPORT.txt"), atomically: true, encoding: .utf8)
            try fileManager.createSymbolicLink(
                at: dmgRoot.appendingPathComponent("Applications"),
                withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
            try runner.run("/usr/bin/hdiutil", [
                "create", "-volname", "MENACE macOS", "-srcfolder", dmgRoot.path,
                "-ov", "-format", "UDZO", outputDMG.path
            ])
            let dmgSHA = try sha256(of: outputDMG)
            report = buildReport(gameVersion: gameVersion, dmgSHA: dmgSHA)
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            dmg = outputDMG
        }

        return BuildResult(app: outputApp, dmg: dmg, report: reportURL)
    }

    private func stageForDMG(_ app: URL, at destination: URL) throws {
        do {
            try runner.run("/bin/cp", ["-cR", app.path, destination.path])
        } catch {
            try? fileManager.removeItem(at: destination)
            try runner.run("/usr/bin/ditto", [app.path, destination.path])
        }
    }

    private func prepareOutput(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            guard options.force else {
                throw BuilderFailure.message("Output already exists: \(url.path). Use --force to replace it.")
            }
            try fileManager.removeItem(at: url)
        }
    }

    private func buildReport(gameVersion: String?, dmgSHA: String?) -> String {
        var lines = [
            "MENACE for macOS - local build report",
            "",
            "Builder: \(Self.version)",
            "Game version label: \(gameVersion ?? "not detected")",
            "Input: \(sourceReportLabel)",
            "Template: \(LockedDependencies.template.version)",
            "Template SHA-256: \(LockedDependencies.template.sha256)",
            "Engine: \(LockedDependencies.engine.version)",
            "Engine SHA-256: \(LockedDependencies.engine.sha256)",
            "App icon: official Steam library artwork",
            "App icon SHA-256: \(LockedDependencies.artwork.sha256)",
            "DXMT: v0.74 from the verified template",
            "Renderer: DXMT / Direct3D 11",
            "Trackpad scroll: discrete Windows wheel compatibility",
            "Host drive mappings: C: only",
            "Code signature: ad hoc, verified",
            "Game launched during build: no"
        ]
        if let dmgSHA { lines.append("DMG SHA-256: \(dmgSHA)") }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private var sourceReportLabel: String {
        switch options.source {
        case .gameFiles: "local user-provided copy (path intentionally omitted)"
        case .steam: "Steam client bootstrap (game downloaded from the user's Steam account)"
        }
    }

    private func wineEnvironment(contents: URL) -> [String: String] {
        [
            "WINEPREFIX": contents.appendingPathComponent("SharedSupport/prefix").path,
            "PATH": contents.appendingPathComponent("SharedSupport/wswine/bin").path + ":/usr/bin:/bin",
            "DYLD_FALLBACK_LIBRARY_PATH": contents.appendingPathComponent("Frameworks").path,
            "WINEDLLOVERRIDES": "mscoree,mshtml=",
            "WINEARCH": "win64",
            "WINEESYNC": "1",
            "WINEMSYNC": "1",
            "WINEDEBUG": "-all"
        ]
    }

    private func overlay(source: URL, destination: URL) throws {
        let canonicalSource = source.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: canonicalSource,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let item as URL in enumerator {
            let sourceComponents = canonicalSource.pathComponents
            let itemComponents = item.resolvingSymlinksInPath().pathComponents
            guard itemComponents.starts(with: sourceComponents) else {
                throw BuilderFailure.message("DXMT payload escaped its expected directory.")
            }
            let relative = itemComponents.dropFirst(sourceComponents.count).joined(separator: "/")
            let target = destination.appendingPathComponent(relative)
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.removeItem(at: target)
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    private func copyDLLs(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where item.pathExtension.lowercased() == "dll" {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: item, to: target)
        }
    }
}

public enum AppIcon {
    // ICNS uses four-byte type codes for each standard and Retina PNG representation.
    private static let iconFiles: [(name: String, pixels: Int, type: String)] = [
        ("icon_16x16.png", 16, "icp4"),
        ("icon_16x16@2x.png", 32, "ic11"),
        ("icon_32x32.png", 32, "icp5"),
        ("icon_32x32@2x.png", 64, "ic12"),
        ("icon_128x128.png", 128, "ic07"),
        ("icon_128x128@2x.png", 256, "ic13"),
        ("icon_256x256.png", 256, "ic08"),
        ("icon_256x256@2x.png", 512, "ic14"),
        ("icon_512x512.png", 512, "ic09"),
        ("icon_512x512@2x.png", 1024, "ic10")
    ]

    static func install(
        artwork: URL,
        in app: URL,
        runner: ProcessRunner,
        rendererExecutable: URL? = nil
    ) throws {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let iconWork = app.deletingLastPathComponent()
            .appendingPathComponent("MENACE-icon-\(UUID().uuidString)", isDirectory: true)
        let iconset = iconWork.appendingPathComponent("MENACE.iconset", isDirectory: true)
        let basePNG = iconWork.appendingPathComponent("MENACE-icon-1024.png")
        let generatedICNS = iconWork.appendingPathComponent("MENACE.icns")
        let output = resources.appendingPathComponent("MENACE.icns")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: iconWork)
        }

        do {
            if let rendererExecutable {
                try runner.run(rendererExecutable.path, ["__render-icon", artwork.path, basePNG.path])
            } else {
                try render(artwork: artwork, output: basePNG)
            }

            for icon in iconFiles {
                try runner.run("/usr/bin/sips", [
                    "--resampleHeightWidth", "\(icon.pixels)", "\(icon.pixels)",
                    basePNG.path, "--out", iconset.appendingPathComponent(icon.name).path
                ])
            }
            try writeICNS(from: iconset, to: generatedICNS)
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: generatedICNS, to: output)
        } catch {
            let fallback = resources.appendingPathComponent("Configure.icns")
            guard FileManager.default.fileExists(atPath: fallback.path) else { throw error }
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: fallback, to: output)
            print("  Warning: custom icon generation failed; using the verified wrapper icon.")
        }
    }

    public static func render(artwork: URL, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                  data: nil,
                  width: 1024,
                  height: 1024,
                  bitsPerComponent: 8,
                  bytesPerRow: 1024 * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw BuilderFailure.message("The verified MENACE artwork could not be rendered.")
        }

        context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let destination = CGRect(x: 32, y: 32, width: 960, height: 960)
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: destination,
            cornerWidth: 210,
            cornerHeight: 210,
            transform: nil
        ))
        context.clip()
        context.interpolationQuality = .high

        let side = min(image.width, image.height)
        let crop = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        )
        guard let cropped = image.cropping(to: crop) else {
            throw BuilderFailure.message("The verified MENACE artwork could not be cropped.")
        }
        context.draw(cropped, in: destination)
        context.restoreGState()

        guard let rendered = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  output as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw BuilderFailure.message("The MENACE app icon could not be encoded.")
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BuilderFailure.message("The MENACE app icon could not be written.")
        }
    }

    private static func writeICNS(from iconset: URL, to output: URL) throws {
        var elements = Data()
        for icon in iconFiles {
            let type = Data(icon.type.utf8)
            guard type.count == 4 else {
                throw BuilderFailure.message("Invalid MENACE icon representation type.")
            }
            let png = try Data(contentsOf: iconset.appendingPathComponent(icon.name))
            guard png.count <= Int(UInt32.max) - 8 else {
                throw BuilderFailure.message("A MENACE icon representation is too large.")
            }
            elements.append(type)
            appendBigEndian(UInt32(png.count + 8), to: &elements)
            elements.append(png)
        }

        guard elements.count <= Int(UInt32.max) - 8 else {
            throw BuilderFailure.message("The MENACE app icon is too large.")
        }
        var icns = Data("icns".utf8)
        appendBigEndian(UInt32(elements.count + 8), to: &icns)
        icns.append(elements)
        try icns.write(to: output, options: .atomic)
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }
}

private final class DependencyStore {
    private let cache: URL
    private let overrideDirectory: URL?
    private let offline: Bool
    private let runner: ProcessRunner
    private let fileManager = FileManager.default

    init(cache: URL, overrideDirectory: URL?, offline: Bool, runner: ProcessRunner) {
        self.cache = cache
        self.overrideDirectory = overrideDirectory
        self.offline = offline
        self.runner = runner
    }

    func file(for dependency: LockedDependency) throws -> URL {
        if let overrideDirectory {
            let override = overrideDirectory.appendingPathComponent(dependency.fileName)
            if fileManager.fileExists(atPath: override.path) {
                try verify(override, dependency: dependency)
                return override
            }
        }

        let cached = cache.appendingPathComponent(dependency.fileName)
        if fileManager.fileExists(atPath: cached.path) {
            do {
                try verify(cached, dependency: dependency)
                return cached
            } catch {
                guard !offline else { throw error }
                try fileManager.removeItem(at: cached)
            }
        }

        guard !offline else {
            throw BuilderFailure.message("Missing offline dependency: \(dependency.fileName)")
        }

        print("  Downloading \(dependency.name) \(dependency.version)")
        let temporary = cache.appendingPathComponent(".\(dependency.fileName).download")
        try? fileManager.removeItem(at: temporary)
        do {
            try runner.run("/usr/bin/curl", [
                "--fail", "--location", "--retry", "3", "--retry-all-errors", "--progress-bar",
                "--output", temporary.path, dependency.url.absoluteString
            ])
            try verify(temporary, dependency: dependency)
            try fileManager.moveItem(at: temporary, to: cached)
            return cached
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func sevenZipExecutable() throws -> URL {
        let archive = try file(for: LockedDependencies.sevenZip)
        let toolRoot = cache.appendingPathComponent("7zip-\(LockedDependencies.sevenZip.version)", isDirectory: true)
        let executable = toolRoot.appendingPathComponent("7zz")
        if fileManager.isExecutableFile(atPath: executable.path) { return executable }

        try? fileManager.removeItem(at: toolRoot)
        try fileManager.createDirectory(at: toolRoot, withIntermediateDirectories: true)
        try runner.run("/usr/bin/tar", ["-xf", archive.path, "-C", toolRoot.path])
        guard fileManager.fileExists(atPath: executable.path) else {
            throw BuilderFailure.message("7-Zip archive did not contain 7zz.")
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func verify(_ file: URL, dependency: LockedDependency) throws {
        let actual = try sha256(of: file)
        guard actual == dependency.sha256 else {
            throw BuilderFailure.message(
                "Checksum mismatch for \(dependency.fileName).\nExpected: \(dependency.sha256)\nActual:   \(actual)"
            )
        }
    }
}

public enum Launcher {
    public static func script(for source: BuildSource) -> String {
        switch source {
        case .gameFiles: gameFilesScript
        case .steam: steamScript
        }
    }

    public static let gameFilesScript = #"""
#!/bin/sh

CONTENTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
USER_NAME="$(id -un)"
LOG_DIR="$CONTENTS_DIR/SharedSupport/prefix/drive_c/users/$USER_NAME/AppData/LocalLow/Overhype Studios/Menace"

mkdir -p "$LOG_DIR"

export WINEPREFIX="$CONTENTS_DIR/SharedSupport/prefix"
export PATH="$CONTENTS_DIR/SharedSupport/wswine/bin:/usr/bin:/bin"
export DYLD_FALLBACK_LIBRARY_PATH="$CONTENTS_DIR/Frameworks"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEESYNC=1
export WINEMSYNC=1
export WINEDEBUG=-all
unset DXMT_LOG_LEVEL DXMT_LOG_PATH

cd "$CONTENTS_DIR/SharedSupport/prefix/drive_c/MENACE" || exit 1
exec "$CONTENTS_DIR/SharedSupport/wswine/bin/wine" \
  'C:\MENACE\Menace.exe' \
  -force-d3d11 \
  -logFile "C:\\users\\$USER_NAME\\AppData\\LocalLow\\Overhype Studios\\Menace\\Player.log" \
  "$@"
"""#

    public static var steamScript: String {
        steamScriptTemplate
            .replacingOccurrences(of: "__STEAM_INSTALLER_URL__", with: LockedDependencies.steamInstaller.url.absoluteString)
            .replacingOccurrences(of: "__STEAM_INSTALLER_SHA256__", with: LockedDependencies.steamInstaller.sha256)
    }

    private static let steamScriptTemplate = #"""
#!/bin/sh

CONTENTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PREFIX="$CONTENTS_DIR/SharedSupport/prefix"
WINE="$CONTENTS_DIR/SharedSupport/wswine/bin/wine"
STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
STEAM_EXE="$STEAM_DIR/steam.exe"
APP_MANIFEST="$STEAM_DIR/steamapps/appmanifest_2432860.acf"
SETUP_DIR="$PREFIX/drive_c/users/$(id -un)/AppData/Local/Temp"
SETUP="$SETUP_DIR/SteamSetup.exe"

export WINEPREFIX="$PREFIX"
export PATH="$CONTENTS_DIR/SharedSupport/wswine/bin:/usr/bin:/bin"
export DYLD_FALLBACK_LIBRARY_PATH="$CONTENTS_DIR/Frameworks"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEESYNC=1
export WINEMSYNC=1
export WINEDEBUG=-all
unset DXMT_LOG_LEVEL DXMT_LOG_PATH

show_message() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
  display dialog (item 1 of argv) with title "MENACE for macOS" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

if [ ! -f "$STEAM_EXE" ]; then
  show_message "First launch will install Valve's official Steam client. Sign in to the account that owns MENACE when Steam opens."
  mkdir -p "$SETUP_DIR"

  if ! /usr/bin/curl --fail --location --retry 3 --retry-all-errors --progress-bar --output "$SETUP" \
    '__STEAM_INSTALLER_URL__'; then
    show_message "Steam could not be downloaded. Check your internet connection and open MENACE again."
    exit 1
  fi

  ACTUAL_SHA="$(/usr/bin/shasum -a 256 "$SETUP" | /usr/bin/awk '{print $1}')"
  if [ "$ACTUAL_SHA" != '__STEAM_INSTALLER_SHA256__' ]; then
    rm -f "$SETUP"
    show_message "Valve changed the Steam installer. For safety, update MENACE for macOS before trying again."
    exit 1
  fi

  if ! "$WINE" "$SETUP" /S; then
    show_message "Steam installation failed. Open MENACE again to retry."
    exit 1
  fi
  rm -f "$SETUP"

  if [ ! -f "$STEAM_EXE" ]; then
    show_message "Steam installation did not finish. Open MENACE again to retry."
    exit 1
  fi
fi

cd "$STEAM_DIR" || exit 1

if [ ! -f "$APP_MANIFEST" ]; then
  show_message "Steam will open the MENACE install screen. Sign in, install the game, then open this app again to play."
  exec "$WINE" "$STEAM_EXE" 'steam://install/2432860'
fi

exec "$WINE" "$STEAM_EXE" \
  -applaunch 2432860 \
  -force-d3d11 \
  "$@"
"""#
}

private enum DmgReadme {
    static func text(for source: BuildSource) -> String {
        switch source {
        case .gameFiles:
            """
            MENACE FOR MACOS

            1. Drag MENACE.app to Applications.
            2. Open it.
            3. If macOS blocks the first launch, right-click the app and choose Open.

            Logs:
            MENACE.app/Contents/SharedSupport/prefix/drive_c/users/<you>/AppData/LocalLow/Overhype Studios/Menace/Player.log

            This is an unofficial compatibility wrapper built from your own Windows copy.
            Do not redistribute this DMG: it contains your copy of the game.
            """
        case .steam:
            """
            MENACE FOR MACOS - STEAM

            1. Drag MENACE.app to Applications.
            2. Open it.
            3. Steam installs. Sign in and install MENACE when prompted.
            4. Open MENACE.app again to play.

            Your password and Steam Guard stay inside Valve's Steam client.
            This is an unofficial compatibility wrapper. No game files are included.
            """
        }
    }
}

public func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
