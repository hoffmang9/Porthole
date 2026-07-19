import XCTest

final class ReleaseBundleE2ETests: XCTestCase {
  override class func setUp() {
    super.setUp()
    TestSupport.requireReleaseBundles()
  }

  func testHostBundleMatchesMachineArchitecture() throws {
    let host = ProcessInfo.processInfo.machineHardwareName
    let expectedBundle = host == "arm64" ? "Porthole-arm64" : "Porthole-x86_64"
    let binary = TestSupport.executable(in: TestSupport.appBundle(named: expectedBundle))
    let archs = try TestSupport.architectures(of: binary)
    XCTAssertTrue(
      archs.contains(host),
      "Expected \(expectedBundle) to include host architecture \(host), got \(archs)"
    )
  }

  func testInfoPlistRequiredKeys() throws {
    for spec in TestSupport.bundleSpecs {
      let app = TestSupport.appBundle(named: spec.name)
      let plist = try TestSupport.readInfoPlist(app)

      XCTAssertEqual(plist["CFBundleExecutable"] as? String, "Porthole")
      XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "org.porthole.app")
      XCTAssertEqual(plist["CFBundleName"] as? String, "Porthole")
      XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
      XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")

      let cameraUsage = plist["NSCameraUsageDescription"] as? String ?? ""
      XCTAssertFalse(cameraUsage.isEmpty, "NSCameraUsageDescription must be set in \(spec.name)")
      XCTAssertTrue(
        cameraUsage.localizedCaseInsensitiveContains("video")
          || cameraUsage.localizedCaseInsensitiveContains("camera"),
        "Camera usage string should describe video/camera access"
      )
    }
  }

  func testBinaryArchitectures() throws {
    for spec in TestSupport.bundleSpecs {
      let binary = TestSupport.executable(in: TestSupport.appBundle(named: spec.name))
      let archs = try TestSupport.architectures(of: binary)
      XCTAssertEqual(archs, spec.expectedArchitectures, "Unexpected architectures in \(spec.name)")
    }
  }

  func testCodesignVerify() throws {
    for spec in TestSupport.bundleSpecs {
      let app = TestSupport.appBundle(named: spec.name)
      let result = try TestSupport.runCommand(
        "/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]
      )
      XCTAssertEqual(
        result.status, 0,
        "codesign verify failed for \(spec.name):\n\(result.stdout)\n\(result.stderr)"
      )
    }
  }

  func testSourceInfoPlistMatchesBuiltBundles() throws {
    let sourceData = try Data(contentsOf: TestSupport.repoRoot.appendingPathComponent("Info.plist"))
    let sourcePlist =
      try PropertyListSerialization.propertyList(from: sourceData, format: nil) as? [String: Any]
    XCTAssertNotNil(sourcePlist)

    let builtPlist = try TestSupport.readInfoPlist(
      TestSupport.appBundle(named: "Porthole-universal"))
    for key in [
      "CFBundleIdentifier", "CFBundleName", "LSMinimumSystemVersion", "NSCameraUsageDescription",
    ] {
      XCTAssertEqual(
        builtPlist[key] as? String, sourcePlist?[key] as? String, "Mismatch for \(key)")
    }
  }
}
