import Foundation
import XCTest

enum TestSupport {
  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  static let distRoot = repoRoot.appendingPathComponent("dist")

  struct BundleSpec {
    let name: String
    let expectedArchitectures: Set<String>
  }

  static let bundleSpecs: [BundleSpec] = [
    BundleSpec(name: "Porthole-arm64", expectedArchitectures: ["arm64"]),
    BundleSpec(name: "Porthole-x86_64", expectedArchitectures: ["x86_64"]),
    BundleSpec(name: "Porthole-universal", expectedArchitectures: ["arm64", "x86_64"]),
  ]

  enum CommandError: Error, CustomStringConvertible {
    case nonZeroExit(command: String, status: Int32, stderr: String)
    case unparsableLipoOutput(String)

    var description: String {
      switch self {
      case .nonZeroExit(let command, let status, let stderr):
        return "\(command) exited with status \(status): \(stderr)"
      case .unparsableLipoOutput(let output):
        return "Could not parse lipo output: \(output)"
      }
    }
  }

  @discardableResult
  static func runCommand(
    _ launchPath: String,
    _ arguments: [String] = [],
    workingDirectory: URL? = nil,
    environment: [String: String]? = nil
  ) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory ?? repoRoot
    if let environment {
      var merged = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        merged[key] = value
      }
      process.environment = merged
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout =
      String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr =
      String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
  }

  static func appBundle(named name: String) -> URL {
    distRoot.appendingPathComponent("\(name).app")
  }

  static func executable(in app: URL) -> URL {
    app.appendingPathComponent("Contents/MacOS/Porthole")
  }

  static func infoPlist(in app: URL) -> URL {
    app.appendingPathComponent("Contents/Info.plist")
  }

  static func readInfoPlist(_ app: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: infoPlist(in: app))
    guard
      let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else {
      throw NSError(
        domain: "PortholeE2ETests", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Info.plist is not a dictionary: \(app.path)"
        ])
    }
    return plist
  }

  static func parseLipoArchitectures(from output: String) -> Set<String>? {
    if output.contains("Architectures in the fat file:") {
      let tail = output.components(separatedBy: "are:").last ?? ""
      return Set(tail.split(whereSeparator: \.isWhitespace).map(String.init))
    }
    if output.contains("Non-fat file:") {
      let tail = output.components(separatedBy: "architecture:").last ?? ""
      return Set([tail.trimmingCharacters(in: .whitespacesAndNewlines)])
    }
    return nil
  }

  static func architectures(of binary: URL) throws -> Set<String> {
    let result = try runCommand("/usr/bin/lipo", ["-info", binary.path])
    guard result.status == 0 else {
      throw CommandError.nonZeroExit(command: "lipo", status: result.status, stderr: result.stderr)
    }
    let output = result.stdout + result.stderr
    guard let architectures = parseLipoArchitectures(from: output) else {
      throw CommandError.unparsableLipoOutput(output)
    }
    return architectures
  }

  static func requireReleaseBundles() {
    for spec in bundleSpecs {
      let app = appBundle(named: spec.name)
      let binary = executable(in: app)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: app.path),
        "Missing \(app.path). Run ./scripts/test-e2e.sh or ./build.sh first."
      )
      XCTAssertTrue(
        FileManager.default.isExecutableFile(atPath: binary.path),
        "Missing executable at \(binary.path). Run ./scripts/test-e2e.sh or ./build.sh first."
      )
    }
  }
}

extension ProcessInfo {
  var machineHardwareName: String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
  }
}
