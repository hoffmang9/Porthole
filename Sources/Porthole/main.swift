// Copyright 2026 Gene Hoffman
// SPDX-License-Identifier: Apache-2.0
//
// Porthole — minimal single-input UVC video viewer for macOS
// Zero-copy pipeline: UVC driver -> IOSurface -> VideoToolbox -> WindowServer.
// The app process never touches frame data.

import AVFoundation
import AppKit
import os

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

  private let log = Logger(subsystem: "org.porthole.app", category: "capture")

  private let session = AVCaptureSession()
  private let previewLayer: AVCaptureVideoPreviewLayer
  private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
  private let sessionQueue = DispatchQueue(label: "capture.session")
  private var devices: [AVCaptureDevice] = []
  private var activeDeviceUniqueID: String?

  override init(frame: NSRect) {
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
    if restoreSelection(selected) {
      return
    }
    autoSelectFirstExternal()
  }

  @objc private func pickerChanged() {
    let index = picker.indexOfSelectedItem - 1  // slot 0 is "no input"
    let device = (index >= 0 && index < devices.count) ? devices[index] : nil
    sessionQueue.async { [self] in
      session.beginConfiguration()
      for input in session.inputs {
        session.removeInput(input)
      }

      if let device {
        do {
          let input = try AVCaptureDeviceInput(device: device)
          guard session.canAddInput(input) else {
            failCapture("Cannot add input for \(device.localizedName)")
            return
          }
          session.addInput(input)
        } catch {
          failCapture("Could not open \(device.localizedName): \(error.localizedDescription)")
          return
        }
      }

      session.commitConfiguration()
      if let device {
        activeDeviceUniqueID = device.uniqueID
        if !session.isRunning { session.startRunning() }
        clearCaptureError()
      } else {
        activeDeviceUniqueID = nil
        if session.isRunning {
          session.stopRunning()
        }
        clearCaptureError()
      }
    }
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
    if device.uniqueID != activeDeviceUniqueID {
      pickerChanged()
    }
    return true
  }

  private func autoSelectFirstExternal() {
    guard let external = devices.first(where: VideoDevices.isExternal) else {
      return
    }
    picker.selectItem(withTitle: external.localizedName)
    pickerChanged()
  }

  private func failCapture(_ message: String) {
    session.commitConfiguration()
    activeDeviceUniqueID = nil
    if session.isRunning {
      session.stopRunning()
    }
    log.error("\(message, privacy: .public)")
    DispatchQueue.main.async { [weak self] in
      self?.selectNoInput(showError: message)
    }
  }

  private func selectNoInput(showError message: String?) {
    if picker.itemTitles.isEmpty {
      repopulatePicker()
    }
    picker.selectItem(withTitle: Self.noInputTitle)
    picker.toolTip = message
    activeDeviceUniqueID = nil
  }

  private func clearCaptureError() {
    DispatchQueue.main.async { [weak self] in
      self?.picker.toolTip = nil
    }
  }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var capturePanel: CapturePanel!

  func applicationDidFinishLaunching(_ note: Notification) {
    capturePanel = CapturePanel(frame: .zero)

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Porthole"
    window.contentView = capturePanel
    window.contentAspectRatio = NSSize(width: 4, height: 3)  // match XGA
    window.collectionBehavior = [.fullScreenPrimary]
    window.center()
    window.makeKeyAndOrderFront(nil)

    requestCameraAccessIfNeeded()
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
    title: "Enter Full Screen",
    action: #selector(NSWindow.toggleFullScreen(_:)),
    keyEquivalent: "f"))
appMenu.addItem(
  NSMenuItem(
    title: "Quit Porthole",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = menubar

app.activate(ignoringOtherApps: true)
app.run()
