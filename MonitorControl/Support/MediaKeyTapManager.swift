import AudioToolbox
import Cocoa
import Foundation
import MediaKeyTap
import os.log

class MediaKeyTapManager: MediaKeyTapDelegate {
  var mediaKeyTap: MediaKeyTap?
  var keyRepeatTimers: [MediaKey: Timer] = [:]

  func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
    guard app.sleepID == 0, app.reconfigureID == 0 else {
      self.showOSDLock(mediaKey)
      return
    }
    let isPressed = event?.keyPressed ?? true
    let isRepeat = event?.keyRepeat ?? false
    if isPressed, self.handleOpenPrefPane(mediaKey: mediaKey, event: event, modifiers: modifiers) {
      return
    }
    var isSmallIncrement = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.shift, .option])) ?? false
    if [.brightnessUp, .brightnessDown].contains(mediaKey), prefs.bool(forKey: PrefKeys.useFineScaleBrightness.rawValue) {
      isSmallIncrement = !isSmallIncrement
    }
    if [.volumeUp, .volumeDown, .mute].contains(mediaKey), prefs.bool(forKey: PrefKeys.useFineScaleVolume.rawValue) {
      isSmallIncrement = !isSmallIncrement
    }
    let isControlModifier = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.control])) ?? false
    let isCommandModifier = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.command])) ?? false
    if isPressed, isControlModifier, mediaKey == .brightnessUp || mediaKey == .brightnessDown {
      self.handleDirectedBrightness(isCommandModifier: isCommandModifier, isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
      return
    } else if isPressed, isCommandModifier, mediaKey == .brightnessDown, self.engageMirror() {
      return
    }
    let oppositeKey: MediaKey? = self.oppositeMediaKey(mediaKey: mediaKey)
    // If the opposite key to the one being held has an active timer, cancel it - we'll be going in the opposite direction
    if let oppositeKey = oppositeKey, let oppositeKeyTimer = self.keyRepeatTimers[oppositeKey], oppositeKeyTimer.isValid {
      oppositeKeyTimer.invalidate()
    } else if let mediaKeyTimer = self.keyRepeatTimers[mediaKey], mediaKeyTimer.isValid {
      // If there's already an active timer for the key being held down, let it run rather than executing it again
      if isRepeat {
        return
      }
      mediaKeyTimer.invalidate()
    }
    self.sendDisplayCommand(mediaKey: mediaKey, isRepeat: isRepeat, isSmallIncrement: isSmallIncrement, isPressed: isPressed)
  }

  func engageMirror() -> Bool {
    return false // MARK: TODO: Here should come the display mirror logic on CMD+Brightness
  }

  func handleDirectedBrightness(isCommandModifier: Bool, isUp: Bool, isSmallIncrement: Bool) {
    if isCommandModifier {
      for externalDisplay in DisplayManager.shared.getExternalDisplays() {
        externalDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      }
      for appleDisplay in DisplayManager.shared.getAppleDisplays() where !appleDisplay.isBuiltIn() {
        appleDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      }
      return
    } else if let internalDisplay = DisplayManager.shared.getBuiltInDisplay() as? AppleDisplay {
      internalDisplay.stepBrightness(isUp: isUp, isSmallIncrement: isSmallIncrement)
      return
    }
  }

  private func showOSDLock(_ mediaKey: MediaKey) {
    if [.brightnessUp, .brightnessDown].contains(mediaKey) {
      OSDUtils.showOSDLockOnAllDisplays(osdImage: 1)
    }
    if [.volumeUp, .volumeDown, .mute].contains(mediaKey) {
      OSDUtils.showOSDLockOnAllDisplays(osdImage: 3)
    }
  }

  private func sendDisplayCommand(mediaKey: MediaKey, isRepeat: Bool, isSmallIncrement: Bool, isPressed: Bool) {
    guard app.sleepID == 0, app.reconfigureID == 0, let affectedDisplays = DisplayManager.shared.getAffectedDisplays(isBrightness: [.brightnessUp, .brightnessDown].contains(mediaKey), isVolume: [.volumeUp, .volumeDown, .mute].contains(mediaKey)) else {
      return
    }
    var wasNotIsPressedVolumeSentAlready = false
    for display in affectedDisplays where display.isEnabled && !display.isVirtual {
      switch mediaKey {
      case .brightnessUp:
        var isAnyDisplayInSwAfterBrightnessMode: Bool = false
        for display in affectedDisplays where ((display as? ExternalDisplay)?.isSwBrightnessNotDefault() ?? false) && !((display as? ExternalDisplay)?.isSw() ?? false) {
          isAnyDisplayInSwAfterBrightnessMode = true
        }
        if isPressed, !(isAnyDisplayInSwAfterBrightnessMode && !(((display as? ExternalDisplay)?.isSwBrightnessNotDefault() ?? false) && !((display as? ExternalDisplay)?.isSw() ?? false))) {
          display.stepBrightness(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
        }
      case .brightnessDown:
        if isPressed {
          display.stepBrightness(isUp: mediaKey == .brightnessUp, isSmallIncrement: isSmallIncrement)
        }
      case .mute:
        // The mute key should not respond to press + hold or keyup
        if !isRepeat, isPressed, let display = display as? ExternalDisplay {
          display.toggleMute()
          if !wasNotIsPressedVolumeSentAlready, !display.isMuted() {
            display.playVolumeChangedSound()
            wasNotIsPressedVolumeSentAlready = true
          }
        }
      case .volumeUp, .volumeDown:
        // volume only matters for external displays
        if let display = display as? ExternalDisplay {
          if isPressed {
            display.stepVolume(isUp: mediaKey == .volumeUp, isSmallIncrement: isSmallIncrement)
          } else if !wasNotIsPressedVolumeSentAlready {
            display.playVolumeChangedSound()
            wasNotIsPressedVolumeSentAlready = true
          }
        }
      default:
        return
      }
    }
  }

  private func oppositeMediaKey(mediaKey: MediaKey) -> MediaKey? {
    if mediaKey == .brightnessUp {
      return .brightnessDown
    } else if mediaKey == .brightnessDown {
      return .brightnessUp
    } else if mediaKey == .volumeUp {
      return .volumeDown
    } else if mediaKey == .volumeDown {
      return .volumeUp
    }
    return nil
  }

  func updateMediaKeyTap() {
    var keys: [MediaKey]
    switch prefs.integer(forKey: PrefKeys.listenFor.rawValue) {
    case Utils.ListenForKeys.brightnessOnlyKeys.rawValue:
      keys = [.brightnessUp, .brightnessDown]
    case Utils.ListenForKeys.volumeOnlyKeys.rawValue:
      keys = [.mute, .volumeUp, .volumeDown]
    case Utils.ListenForKeys.none.rawValue:
      keys = []
    default:
      keys = [.brightnessUp, .brightnessDown, .mute, .volumeUp, .volumeDown]
    }
    // Remove keys if no external displays are connected
    var isInternalDisplayOnly = true
    for display in DisplayManager.shared.getAllDisplays() where display is ExternalDisplay {
      isInternalDisplayOnly = false
    }
    if isInternalDisplayOnly {
      let keysToDelete: [MediaKey] = [.volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown]
      keys.removeAll { keysToDelete.contains($0) }
    }
    // Remove volume related keys if audio device is controllable
    if let defaultAudioDevice = app.coreAudio.defaultOutputDevice {
      let keysToDelete: [MediaKey] = [.volumeUp, .volumeDown, .mute]
      if !prefs.bool(forKey: PrefKeys.allScreensVolume.rawValue), prefs.bool(forKey: PrefKeys.useAudioDeviceNameMatching.rawValue) {
        if DisplayManager.shared.updateAudioControlTargetDisplays(deviceName: defaultAudioDevice.name) == 0 {
          keys.removeAll { keysToDelete.contains($0) }
        }
      } else if defaultAudioDevice.canSetVirtualMasterVolume(scope: .output) == true {
        keys.removeAll { keysToDelete.contains($0) }
      }
    }
    self.mediaKeyTap?.stop()
    // returning an empty array listens for all mediakeys in MediaKeyTap
    if keys.count > 0 {
      self.mediaKeyTap = MediaKeyTap(delegate: self, on: KeyPressMode.keyDownAndUp, for: keys, observeBuiltIn: true)
      self.mediaKeyTap?.start()
    }
  }

  func handleOpenPrefPane(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) -> Bool {
    guard let modifiers = modifiers else { return false }
    if !(modifiers.contains(.option) && !modifiers.contains(.shift)) {
      return false
    }
    if event?.keyRepeat == true {
      return false
    }
    switch mediaKey {
    case .brightnessUp, .brightnessDown:
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
    case .mute, .volumeUp, .volumeDown:
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
    default:
      return false
    }
    return true
  }
}
