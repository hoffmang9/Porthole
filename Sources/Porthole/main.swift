// Copyright 2026 Gene Hoffman
// SPDX-License-Identifier: Apache-2.0
//
// Porthole — minimal single-input UVC video viewer for macOS
// Zero-copy pipeline: UVC driver -> IOSurface -> VideoToolbox -> WindowServer.
// The app process never touches frame data.

import AppKit
import AVFoundation

// MARK: - One capture panel (preview layer + device picker)

final class CapturePanel: NSView {

    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sessionQueue = DispatchQueue(label: "capture.session")
    private var devices: [AVCaptureDevice] = []

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

        refreshDevices()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshDevices),
            name: .AVCaptureDeviceWasConnected, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshDevices),
            name: .AVCaptureDeviceWasDisconnected, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation on resize
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    // Fade the picker out when the mouse isn't over the panel.
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { picker.animator().alphaValue = 1 }
    override func mouseExited(with event: NSEvent)  { picker.animator().alphaValue = 0.02 }

    @objc private func refreshDevices() {
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.external, .builtInWideAngleCamera]
        } else {
            types = [.externalUnknown, .builtInWideAngleCamera]
        }
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices

        let selected = picker.titleOfSelectedItem
        picker.removeAllItems()
        picker.addItem(withTitle: "— no input —")
        devices.forEach { picker.addItem(withTitle: $0.localizedName) }
        if let selected, selected != "— no input —",
           picker.itemTitles.contains(selected) {
            picker.selectItem(withTitle: selected)
            return
        }
        // Nothing chosen yet: auto-select the first external device (the
        // capture card), so the app is zero-touch on boot. Built-in and
        // Continuity cameras are skipped.
        if let ext = devices.first(where: {
            if #available(macOS 14.0, *) { return $0.deviceType == .external }
            else { return $0.deviceType == .externalUnknown }
        }) {
            picker.selectItem(withTitle: ext.localizedName)
            pickerChanged()
        }
    }

    @objc private func pickerChanged() {
        let index = picker.indexOfSelectedItem - 1   // slot 0 is "no input"
        let device = (index >= 0 && index < devices.count) ? devices[index] : nil
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            if let device, let input = try? AVCaptureDeviceInput(device: device) {
                if session.canAddInput(input) { session.addInput(input) }
            }
            session.commitConfiguration()
            if device != nil {
                if !session.isRunning { session.startRunning() }
            } else {
                if session.isRunning { session.stopRunning() }
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        AVCaptureDevice.requestAccess(for: .video) { _ in }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Porthole"
        window.contentView = CapturePanel(frame: .zero)
        window.contentAspectRatio = NSSize(width: 4, height: 3)  // match XGA
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
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
appMenu.addItem(NSMenuItem(title: "Enter Full Screen",
                           action: #selector(NSWindow.toggleFullScreen(_:)),
                           keyEquivalent: "f"))
appMenu.addItem(NSMenuItem(title: "Quit Porthole",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = menubar

app.activate(ignoringOtherApps: true)
app.run()
