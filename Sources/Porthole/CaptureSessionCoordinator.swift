// Copyright 2026 Gene Hoffman
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import CoreMedia
import os

/// Owns capture-session mutations on a dedicated queue and guards async UI callbacks
/// against stale work via a monotonic generation counter.
final class CaptureSessionCoordinator {

  let session: AVCaptureSession

  private let queue = DispatchQueue(label: "capture.session")
  private let log = Logger(subsystem: "org.porthole.app", category: "capture")
  private var generation: UInt64 = 0

  var onFailure: ((String) -> Void)?
  var onErrorCleared: (() -> Void)?
  /// Active format pixel dimensions on the main queue, or `nil` when there is no video.
  var onVideoDimensionsChanged: ((CGSize?) -> Void)?

  init(session: AVCaptureSession) {
    self.session = session
  }

  /// Invalidates in-flight capture work and tears down the session.
  func invalidate() {
    queue.sync {
      generation += 1
      tearDownSession()
      reportVideoDimensions(nil, generation: generation)
    }
  }

  func setDevice(_ device: AVCaptureDevice?) {
    queue.async { [self] in
      generation += 1
      configure(device: device, generation: generation)
    }
  }

  /// Hot-plug list refresh: rebind only when the session input differs from `device`.
  func syncDeviceIfNeeded(_ device: AVCaptureDevice) {
    queue.async { [self] in
      guard Self.activeDeviceUniqueID(in: session) != device.uniqueID else { return }
      generation += 1
      configure(device: device, generation: generation)
    }
  }

  private func configure(device: AVCaptureDevice?, generation: UInt64) {
    session.beginConfiguration()
    for input in session.inputs {
      session.removeInput(input)
    }

    if let device {
      do {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
          session.commitConfiguration()
          failCapture("Cannot add input for \(device.localizedName)", generation: generation)
          return
        }
        session.addInput(input)
      } catch {
        session.commitConfiguration()
        failCapture(
          "Could not open \(device.localizedName): \(error.localizedDescription)",
          generation: generation)
        return
      }
    }

    session.commitConfiguration()

    if device != nil {
      if !session.isRunning { session.startRunning() }
    } else if session.isRunning {
      session.stopRunning()
    }
    reportVideoDimensions(device.flatMap(Self.videoDimensions(of:)), generation: generation)
    clearCaptureError(generation: generation)
  }

  private static func videoDimensions(of device: AVCaptureDevice) -> CGSize? {
    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    guard dims.width > 0, dims.height > 0 else { return nil }
    return CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
  }

  private func reportVideoDimensions(_ dimensions: CGSize?, generation: UInt64) {
    dispatchUIIfCurrent(generation: generation) { [weak self] in
      self?.onVideoDimensionsChanged?(dimensions)
    }
  }

  private func failCapture(_ message: String, generation: UInt64) {
    tearDownSession()
    log.error("\(message, privacy: .public)")
    reportVideoDimensions(nil, generation: generation)
    dispatchUIIfCurrent(generation: generation) { [weak self] in
      self?.onFailure?(message)
    }
  }

  private func clearCaptureError(generation: UInt64) {
    dispatchUIIfCurrent(generation: generation) { [weak self] in
      self?.onErrorCleared?()
    }
  }

  /// Runs `block` on the main queue only if `generation` is still current when the block runs.
  private func dispatchUIIfCurrent(generation: UInt64, _ block: @escaping () -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      // Re-check on sessionQueue at execution time, not schedule time, so a later
      // successful rebind can drop stale failure/error callbacks.
      let stillCurrent = self.queue.sync { self.generation == generation }
      guard stillCurrent else { return }
      block()
    }
  }

  private func tearDownSession() {
    session.beginConfiguration()
    for input in session.inputs {
      session.removeInput(input)
    }
    session.commitConfiguration()
    if session.isRunning {
      session.stopRunning()
    }
  }

  private static func activeDeviceUniqueID(in session: AVCaptureSession) -> String? {
    for input in session.inputs {
      guard let deviceInput = input as? AVCaptureDeviceInput else { continue }
      return deviceInput.device.uniqueID
    }
    return nil
  }
}
