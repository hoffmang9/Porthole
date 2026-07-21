// Copyright 2026 Gene Hoffman
// SPDX-License-Identifier: Apache-2.0
//
// Porthole — minimal single-input UVC video viewer for macOS
// Zero-copy pipeline: UVC driver -> IOSurface -> VideoToolbox -> WindowServer.
// The app process never touches frame data.

import AVFoundation
import AppKit

// MARK: - Video device discovery

private enum VideoDevices {
  private static var externalType: AVCaptureDevice.DeviceType {
    if #available(macOS 14.0, *) {
      return .external
    }
    return .externalUnknown
  }

  static var discoveryTypes: [AVCaptureDevice.DeviceType] {
    [externalType, .builtInWideAngleCamera]
  }

  static func isExternal(_ device: AVCaptureDevice) -> Bool {
    device.deviceType == externalType
  }
}

// MARK: - One capture panel (preview layer + device picker)

final class CapturePanel: NSView {

  private static let noInputTitle = "— no input —"

  private let session = AVCaptureSession()
  let coordinator: CaptureSessionCoordinator
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
  private var devices: [AVCaptureDevice] = []

  override init(frame: NSRect) {
    coordinator = CaptureSessionCoordinator(session: session)
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    super.init(frame: frame)

    wantsLayer = true
    layer = CALayer()
    layer?.backgroundColor = NSColor.black.cgColor

    previewLayer.videoGravity = .resizeAspect
    previewLayer.frame = bounds
    layer?.addSublayer(previewLayer)

    picker.target = self
    picker.action = #selector(pickerChanged)
    picker.translatesAutoresizingMaskIntoConstraints = false
    addSubview(picker)
    NSLayoutConstraint.activate([
      picker.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      picker.centerXAnchor.constraint(equalTo: centerXAnchor),
      picker.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
    ])

    coordinator.onFailure = { [weak self] message in
      self?.selectNoInput(showError: message)
    }
    coordinator.onErrorCleared = { [weak self] in
      self?.picker.toolTip = nil
    }

    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshDevices),
      name: .AVCaptureDeviceWasConnected, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshDevices),
      name: .AVCaptureDeviceWasDisconnected, object: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  func start() {
    refreshDevices()
  }

  func resetWithoutCameraAccess() {
    coordinator.invalidate()
    devices = []
    repopulatePicker()
    selectNoInput(
      showError: "Camera access is required to display video inputs.")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)  // no implicit animation on resize
    previewLayer.frame = bounds
    CATransaction.commit()
  }

  // Fade the picker out when the mouse isn't over the panel.
  override func updateTrackingAreas() {
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self, userInfo: nil))
    super.updateTrackingAreas()
  }
  override func mouseEntered(with event: NSEvent) { picker.animator().alphaValue = 1 }
  override func mouseExited(with event: NSEvent) { picker.animator().alphaValue = 0.02 }

  @objc func refreshDevices() {
    discoverDevices()
    let selected = picker.titleOfSelectedItem
    repopulatePicker()
    if selected == Self.noInputTitle {
      picker.selectItem(withTitle: Self.noInputTitle)
      pickerChanged()
      return
    }
    if restoreSelection(selected) {
      return
    }
    selectFallbackDevice()
  }

  @objc private func pickerChanged() {
    let index = picker.indexOfSelectedItem - 1  // slot 0 is "no input"
    let device = (index >= 0 && index < devices.count) ? devices[index] : nil
    coordinator.setDevice(device)
  }

  private func discoverDevices() {
    devices =
      AVCaptureDevice.DiscoverySession(
        deviceTypes: VideoDevices.discoveryTypes,
        mediaType: .video,
        position: .unspecified
      ).devices
  }

  private func repopulatePicker() {
    picker.removeAllItems()
    picker.addItem(withTitle: Self.noInputTitle)
    for device in devices {
      picker.addItem(withTitle: device.localizedName)
    }
  }

  private func restoreSelection(_ selected: String?) -> Bool {
    guard let selected, selected != Self.noInputTitle,
      let device = devices.first(where: { $0.localizedName == selected })
    else {
      return false
    }
    picker.selectItem(withTitle: selected)
    coordinator.syncDeviceIfNeeded(device)
    return true
  }

  private func selectFallbackDevice() {
    if let external = devices.first(where: VideoDevices.isExternal) {
      picker.selectItem(withTitle: external.localizedName)
    } else {
      picker.selectItem(withTitle: Self.noInputTitle)
    }
    pickerChanged()
  }

  private func selectNoInput(showError message: String?) {
    if picker.itemTitles.isEmpty {
      repopulatePicker()
    }
    picker.selectItem(withTitle: Self.noInputTitle)
    picker.toolTip = message
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
  /// Fallback lock when there is no active video (matches the default 1024×768 window).
  private static let defaultContentAspectRatio = NSSize(width: 4, height: 3)

  private var window: NSWindow!
  private var capturePanel: CapturePanel!
  /// Active capture pixel size (`nil` = no input). Source of truth for aspect lock and size menus.
  private var videoSize: CGSize?

  /// Capture size usable for Actual Size / Double Size (`nil` when unavailable or full screen).
  private var scalableVideoSize: CGSize? {
    guard !window.styleMask.contains(.fullScreen),
      let videoSize, videoSize.width > 0, videoSize.height > 0
    else {
      return nil
    }
    return videoSize
  }

  private var videoAspectRatio: NSSize {
    videoSize.map { NSSize(width: $0.width, height: $0.height) }
      ?? Self.defaultContentAspectRatio
  }

  func applicationDidFinishLaunching(_ note: Notification) {
    capturePanel = CapturePanel(frame: .zero)
    capturePanel.coordinator.onVideoDimensionsChanged = { [weak self] dimensions in
      self?.applyVideoDimensions(dimensions)
    }

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Porthole"
    window.contentView = capturePanel
    window.delegate = self
    applyVideoDimensions(nil)
    window.collectionBehavior = [.fullScreenPrimary]
    window.center()
    window.makeKeyAndOrderFront(nil)

    requestCameraAccessIfNeeded()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    reshapeContentToMatchAspectRatio()
  }

  @objc func restoreActualSize(_ sender: Any?) {
    guard let size = scalableVideoSize else { return }
    applyContentSize(size)
  }

  @objc func setDoubleSize(_ sender: Any?) {
    guard let size = scalableVideoSize else { return }
    applyContentSize(NSSize(width: size.width * 2, height: size.height * 2))
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(restoreActualSize), #selector(setDoubleSize):
      return scalableVideoSize != nil
    default:
      return true
    }
  }

  /// Locks resize to the video aspect and reshapes the window so the preview is not letterboxed.
  private func applyVideoDimensions(_ dimensions: CGSize?) {
    videoSize = dimensions
    window.contentAspectRatio = videoAspectRatio
    reshapeContentToMatchAspectRatio()
  }

  /// Fits content to the current aspect within the visible screen. No-op while full screen.
  private func reshapeContentToMatchAspectRatio() {
    let ratio = videoAspectRatio
    guard ratio.width > 0, ratio.height > 0 else { return }

    let current = window.contentRect(forFrameRect: window.frame).size
    guard current.width > 0 else { return }

    applyContentSize(
      NSSize(
        width: current.width,
        height: current.width * ratio.height / ratio.width))
  }

  /// Applies `desired` content size (aspect preserved while clamping) and keeps the frame on-screen.
  /// No-op while full screen.
  private func applyContentSize(_ desired: NSSize) {
    guard !window.styleMask.contains(.fullScreen) else { return }
    guard desired.width > 0, desired.height > 0 else { return }

    let current = window.contentRect(forFrameRect: window.frame).size
    var contentWidth = desired.width
    var contentHeight = desired.height

    if let screen = window.screen ?? NSScreen.main {
      let chromeWidth = window.frame.width - current.width
      let chromeHeight = window.frame.height - current.height
      let maxWidth = max(screen.visibleFrame.width - chromeWidth, 1)
      let maxHeight = max(screen.visibleFrame.height - chromeHeight, 1)
      if contentWidth > maxWidth {
        contentWidth = maxWidth
        contentHeight = contentWidth * desired.height / desired.width
      }
      if contentHeight > maxHeight {
        contentHeight = maxHeight
        contentWidth = contentHeight * desired.width / desired.height
      }
    }

    if abs(current.width - contentWidth) >= 0.5
      || abs(current.height - contentHeight) >= 0.5
    {
      window.setContentSize(NSSize(width: contentWidth, height: contentHeight))
    }

    guard let screen = window.screen ?? NSScreen.main else { return }
    var frame = window.frame
    let visible = screen.visibleFrame
    if frame.maxX > visible.maxX { frame.origin.x -= frame.maxX - visible.maxX }
    if frame.maxY > visible.maxY { frame.origin.y -= frame.maxY - visible.maxY }
    if frame.minX < visible.minX { frame.origin.x = visible.minX }
    if frame.minY < visible.minY { frame.origin.y = visible.minY }
    if abs(frame.origin.x - window.frame.origin.x) >= 0.5
      || abs(frame.origin.y - window.frame.origin.y) >= 0.5
    {
      window.setFrame(frame, display: true)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
    true
  }

  private func requestCameraAccessIfNeeded() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      capturePanel.start()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.capturePanel.start()
          } else {
            self.showCameraAccessDenied()
          }
        }
      }
    case .denied, .restricted:
      showCameraAccessDenied()
    @unknown default:
      showCameraAccessDenied()
    }
  }

  private func showCameraAccessDenied() {
    capturePanel.resetWithoutCameraAccess()
    NSAlert(
      error: NSError(
        domain: "org.porthole.app", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Camera Access Required",
          NSLocalizedRecoverySuggestionErrorKey:
            "Allow camera access for Porthole in System Settings → Privacy & Security → Camera.",
        ]
      )
    ).runModal()
  }
}

// MARK: - Entry point (no storyboard, no nib)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

let menubar = NSMenu()

let appMenuItem = NSMenuItem()
menubar.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(
  NSMenuItem(
    title: "Quit Porthole",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"))
appMenuItem.submenu = appMenu

let windowMenuItem = NSMenuItem()
windowMenuItem.title = "Window"
menubar.addItem(windowMenuItem)
let windowMenu = NSMenu(title: "Window")
let actualSizeItem = NSMenuItem(
  title: "Actual Size",
  action: #selector(AppDelegate.restoreActualSize(_:)),
  keyEquivalent: "1")
actualSizeItem.target = delegate
windowMenu.addItem(actualSizeItem)
let doubleSizeItem = NSMenuItem(
  title: "Double Size",
  action: #selector(AppDelegate.setDoubleSize(_:)),
  keyEquivalent: "2")
doubleSizeItem.target = delegate
windowMenu.addItem(doubleSizeItem)
windowMenu.addItem(NSMenuItem.separator())
windowMenu.addItem(
  NSMenuItem(
    title: "Enter Full Screen",
    action: #selector(NSWindow.toggleFullScreen(_:)),
    keyEquivalent: "f"))
windowMenuItem.submenu = windowMenu
app.windowsMenu = windowMenu

app.mainMenu = menubar

app.activate(ignoringOtherApps: true)
app.run()
