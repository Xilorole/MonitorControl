import Cocoa
import os.log
import Preferences
import ServiceManagement

class MainPrefsViewController: NSViewController, PreferencePane {
  let preferencePaneIdentifier = Preferences.PaneIdentifier.main
  let preferencePaneTitle: String = NSLocalizedString("General", comment: "Shown in the main prefs window")

  var toolbarItemIcon: NSImage {
    if #available(macOS 11.0, *) {
      return NSImage(systemSymbolName: "switch.2", accessibilityDescription: "Display")!
    } else {
      return NSImage(named: NSImage.infoName)!
    }
  }

  let prefs = UserDefaults.standard

  @IBOutlet var startAtLogin: NSButton!
  @IBOutlet var lowerSwAfterBrightness: NSButton!
  @IBOutlet var fallbackSw: NSButton!
  @IBOutlet var showAdvancedDisplays: NSButton!
  @IBOutlet var restoreLastSavedValuesOff: NSButton!
  @IBOutlet var restoreLastSavedValuesOn: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
  }

  @available(macOS, deprecated: 10.10)
  override func viewWillAppear() {
    super.viewWillAppear()
    self.populateSettings()
  }

  @available(macOS, deprecated: 10.10)
  func populateSettings() {
    // This is marked as deprectated but according to the function header it still does not have a replacement as of macOS 12 Monterey and is valid to use.
    let startAtLogin = (SMCopyAllJobDictionaries(kSMDomainUserLaunchd).takeRetainedValue() as? [[String: AnyObject]])?.first { $0["Label"] as? String == "\(Bundle.main.bundleIdentifier!)Helper" }?["OnDemand"] as? Bool ?? false
    self.startAtLogin.state = startAtLogin ? .on : .off
    self.lowerSwAfterBrightness.state = self.prefs.bool(forKey: Utils.PrefKeys.lowerSwAfterBrightness.rawValue) ? .on : .off
    self.fallbackSw.state = self.prefs.bool(forKey: Utils.PrefKeys.fallbackSw.rawValue) ? .on : .off
    self.showAdvancedDisplays.state = self.prefs.bool(forKey: Utils.PrefKeys.showAdvancedDisplays.rawValue) ? .on : .off
    self.restoreLastSavedValuesOff.state = self.prefs.bool(forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue) ? .off : .on
    self.restoreLastSavedValuesOn.state = self.prefs.bool(forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue) ? .on : .off
  }

  @IBAction func startAtLoginClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      Utils.setStartAtLogin(enabled: true)
    case .off:
      Utils.setStartAtLogin(enabled: false)
    default: break
    }
  }

  @IBAction func lowerSwAfterBrightnessClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      self.prefs.set(true, forKey: Utils.PrefKeys.lowerSwAfterBrightness.rawValue)
    case .off:
      self.prefs.set(false, forKey: Utils.PrefKeys.lowerSwAfterBrightness.rawValue)
      DisplayManager.shared.resetSwBrightnessForAllDisplays()
    default: break
    }
    app.updateMenus()
  }

  @IBAction func fallbackSwClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      self.prefs.set(true, forKey: Utils.PrefKeys.fallbackSw.rawValue)
    case .off:
      self.prefs.set(false, forKey: Utils.PrefKeys.fallbackSw.rawValue)
    default: break
    }
    DisplayManager.shared.resetSwBrightnessForAllDisplays()
    app.updateMenus()
  }

  @IBAction func restoreLastSavedValuesOffClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      self.prefs.set(false, forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue)
      self.restoreLastSavedValuesOn.state = .off
    case .off:
      self.prefs.set(true, forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue)
      self.restoreLastSavedValuesOn.state = .on
    default: break
    }
  }

  @IBAction func restoreLastSavedValuesOnClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      self.prefs.set(true, forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue)
      self.restoreLastSavedValuesOff.state = .off
    case .off:
      self.prefs.set(false, forKey: Utils.PrefKeys.restoreLastSavedValues.rawValue)
      self.restoreLastSavedValuesOff.state = .on
    default: break
    }
  }

  @IBAction func showAdvancedClicked(_ sender: NSButton) {
    switch sender.state {
    case .on:
      self.prefs.set(true, forKey: Utils.PrefKeys.showAdvancedDisplays.rawValue)
    case .off:
      self.prefs.set(false, forKey: Utils.PrefKeys.showAdvancedDisplays.rawValue)
    default: break
    }
    NotificationCenter.default.post(name: Notification.Name(Utils.PrefKeys.displayListUpdate.rawValue), object: nil)
  }

  @available(macOS, deprecated: 10.10)
  func resetSheetModalHander(modalResponse: NSApplication.ModalResponse) {
    if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
      NotificationCenter.default.post(name: Notification.Name(Utils.PrefKeys.preferenceReset.rawValue), object: nil)
      self.populateSettings()
    }
  }

  @available(macOS, deprecated: 10.10)
  @IBAction func resetPrefsClicked(_: NSButton) {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Reset Preferences?", comment: "Shown in the alert dialog")
    alert.informativeText = NSLocalizedString("Are you sure you want to reset all preferences?", comment: "Shown in the alert dialog")
    alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Shown in the alert dialog"))
    alert.addButton(withTitle: NSLocalizedString("No", comment: "Shown in the alert dialog"))
    alert.alertStyle = NSAlert.Style.warning
    if let window = self.view.window {
      alert.beginSheetModal(for: window, completionHandler: { modalResponse in self.resetSheetModalHander(modalResponse: modalResponse) })
    }
  }
}
