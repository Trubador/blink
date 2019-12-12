//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

import UIKit

class BlinkCommand: UIKeyCommand {
  var bindingAction: KeyBindingAction = .none
}

class SmarterTermInput: KBWebView {
  
  private var _kbView = KBView()
  private var _hideSmartKeysWithHKB = !BKUserConfigurationManager.userSettingsValue(
  forKey: BKUserConfigShowSmartKeysWithXKeyBoard)
  private var _inputAccessoryView: UIView? = nil
  var blinkKeyCommands: [BlinkCommand] = []
  
  var device: TermDevice? = nil {
    didSet {
      reportStateReset()
    }
  }
  
  override init(frame: CGRect, configuration: WKWebViewConfiguration) {
    super.init(frame: frame, configuration: configuration)
    
    self.tintColor = .cyan
    
    _setKBStyle()
    
    if traitCollection.userInterfaceIdiom == .pad {
      setupAssistantItem()
    } else {
      setupAccessoryView()
    }
    
    _kbView.keyInput = self
    _kbView.lang = textInputMode?.primaryLanguage ?? ""
    
    
    KBSound.isMutted = BKUserConfigurationManager.userSettingsValue(
      forKey: BKUserConfigMuteSmartKeysPlaySound)
    
    let nc = NotificationCenter.default
      
    nc.addObserver(
      self,
      selector: #selector(_inputModeChanged),
      name: UITextInputMode.currentInputModeDidChangeNotification, object: nil)

    nc.addObserver(self, selector: #selector(_updateSettings), name: NSNotification.Name.BKUserConfigChanged, object: nil)
    nc.addObserver(self, selector: #selector(_setKBStyle), name: NSNotification.Name(rawValue: BKAppearanceChanged), object: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func ready() {
    super.ready()
    reportLang(_kbView.lang)
    
    if traitCollection.userInterfaceIdiom == .pad {
      setupAssistantItem()
    } else {
      setupAccessoryView()
    }
    
    reloadInputViews()
  }
  
  override func configure(_ cfg: KBConfig) {
    blinkKeyCommands = cfg.shortcuts.map { shortcut in
      let cmd = BlinkCommand(
        title: shortcut.action.isCommand ? shortcut.title : "",
        image: nil,
        action: #selector(SpaceController._onBlinkCommand(_:)),
        input: shortcut.input,
        modifierFlags: shortcut.modifiers,
        propertyList: nil
      )
      cmd.bindingAction = shortcut.action
      return cmd
    }
    super.configure(cfg)
  }
  
  @objc private func _setKBStyle() {
    let style = BKDefaults.keyboardStyle();
    switch style {
    case .light:
      self.overrideUserInterfaceStyle = .light
    case .dark:
      self.overrideUserInterfaceStyle = .dark
    default:
      self.overrideUserInterfaceStyle = .unspecified
    }
  }

  @objc private func _updateSettings() {
    
    KBSound.isMutted = BKUserConfigurationManager.userSettingsValue(
    forKey: BKUserConfigMuteSmartKeysPlaySound)
    
    let hideSmartKeysWithHKB = !BKUserConfigurationManager.userSettingsValue(
    forKey: BKUserConfigShowSmartKeysWithXKeyBoard)
    
    if hideSmartKeysWithHKB != _hideSmartKeysWithHKB {
      _hideSmartKeysWithHKB = hideSmartKeysWithHKB
      if traitCollection.userInterfaceIdiom == .pad {
        setupAssistantItem()
      } else {
        setupAccessoryView()
      }
      refreshInputViews()
    }
  }
  
  // overriding chain
  override var next: UIResponder? {
    guard let responder = device?.view?.superview
    else {
      return super.next
    }
    return responder
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    guard
      let window = window,
      let scene = window.windowScene
    else {
      return
    }
    if traitCollection.userInterfaceIdiom == .phone {
      _kbView.traits.isPortrait = scene.interfaceOrientation.isPortrait
    }
  }
  
  override func onOut(_ data: String) {
    defer {
      _kbView.turnOffUntracked()
    }
    
    device?.view.displayInput(data)
    
    let ctrlC = "\u{0003}"
    let ctrlD = "\u{0004}"
    
    if data == ctrlC || data == ctrlD,
      device?.delegate?.handleControl(data) == true {
      return
    }
    device?.write(data)
  }
  
  override func onCommand(_ command: String) {
    _kbView.turnOffUntracked()
    if let cmd = Command(rawValue: command) {
      var n = next
      while let r = n {
        if let sc = r as? SpaceController {
          sc._onCommand(cmd)
          return
        }
        n = r.next
      }
    }
  }
  
  func matchCommand(input: String, flags: UIKeyModifierFlags) -> (UIKeyCommand, UIResponder)? {
    var result: (UIKeyCommand, UIResponder)? = nil

    var iterator: UIResponder? = self

    while let responder = iterator {
      if let cmd = responder.keyCommands?.first(
        where: { $0.input == input && $0.modifierFlags == flags}),
        let action = cmd.action,
        responder.canPerformAction(action, withSender: self)
        {
        result = (cmd, responder)
      }
      iterator = responder.next
    }

    return result
  }
  
  func reset() {
    
  }
  
  @objc func _inputModeChanged() {
    DispatchQueue.main.async {
      let lang = self.textInputMode?.primaryLanguage ?? ""
      self._kbView.lang = lang
      self.reportLang(lang)
    }
  }
  
  func contentView() -> UIView? {
    scrollView.subviews.first
  }
  
  override var inputAssistantItem: UITextInputAssistantItem {
    let item = super.inputAssistantItem
    if item.trailingBarButtonGroups.count > 1 {
      item.leadingBarButtonGroups = []
      item.trailingBarButtonGroups = [item.trailingBarButtonGroups[0]]
      _kbView.setNeedsLayout()
    }
    return item
  }
  
  override func becomeFirstResponder() -> Bool {

    let res = super.becomeFirstResponder()//contentView()?.becomeFirstResponder()

    device?.focus()
    _kbView.isHidden = false
    _kbView.invalidateIntrinsicContentSize()
    refreshInputViews()
    
    _disableTextSelectionView()
    return res == true
  }
  
  private func _disableTextSelectionView() {
    let subviews = scrollView.subviews
    guard
      subviews.count > 2,
      let v = subviews[1].subviews.first
    else {
      return
    }
    NotificationCenter.default.removeObserver(v)
  }
  
  var isRealFirstResponder: Bool {
    contentView()?.isFirstResponder == true
  }
  
  func refreshInputViews() {
    if traitCollection.userInterfaceIdiom != .pad {
      return;
    }

    // Double relaod inputs fixes: https://github.com/blinksh/blink/issues/803
    contentView()?.inputAssistantItem.leadingBarButtonGroups = [.init(barButtonItems: [UIBarButtonItem()], representativeItem: nil)]
    reloadInputViews()
    if (_hideSmartKeysWithHKB && _kbView.traits.isHKBAttached) {
      _removeSmartKeys()
      reloadInputViews()
    }
  }
  
  @objc func copyLink(_ sender: Any) {
    guard let url = device?.view?.detectedLink else {
      return
    }
    UIPasteboard.general.url = url
    device?.view?.cleanSelection()
  }
  
  @objc func openLink(_ sender: Any) {
    guard let url = device?.view?.detectedLink else {
      return
    }
    device?.view?.cleanSelection()
    
    blink_openurl(url)
  }
  
  @objc func pasteSelection(_ sender: Any) {
    device?.view?.pasteSelection(sender)
  }
  
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    switch action {
    case #selector(UIResponder.paste(_:)):
      return true
    case #selector(UIResponder.copy(_:)),
         #selector(TermView.pasteSelection(_:)):
      return device?.view?.hasSelection == true
    case #selector(Self.copyLink(_:)),
         #selector(Self.openLink(_:)):
      return device?.view?.detectedLink != nil
    default:
      return super.canPerformAction(action, withSender: sender)
    }
  }
  
  override func onMods() {
    _kbView.stopRepeats()
  }
  
  override func onIME(_ event: String, data: String) {
    if event == "compositionstart" && data.isEmpty {
    } else if event == "compositionend" {
      _kbView.traits.isIME = false
      device?.view?.setIme("", completionHandler: nil)
    } else {
      _kbView.traits.isIME = true
      device?.view?.setIme(data) {  (data, error) in
        guard
          error == nil,
          let resp = data as? [String: Any],
          let markedRect = resp["markedRect"] as? String
        else {
          return
        }
        var rect = NSCoder.cgRect(for: markedRect)
        let suggestionsHeight: CGFloat = 44
        let maxY = rect.maxY
        let minY = rect.minY
        if maxY - suggestionsHeight < 0 {
          rect.origin.y = maxY
        } else {
          rect.origin.y = minY
        }
        
        rect.size.height = 0
        rect.size.width = 0
        
        if let r = self.device?.view?.convert(rect, to: self.superview) {
          self.frame = r
        }
      }
    }
  }
  
  override var canBecomeFirstResponder: Bool { true }
  
  override func resignFirstResponder() -> Bool {
    let res = super.resignFirstResponder()
    if res {
      device?.blur()
      _kbView.isHidden = true
      _inputAccessoryView?.isHidden = true
      reloadInputViews()
    }
    return res
  }
  
  func _removeSmartKeys() {
    _inputAccessoryView = UIView(frame: .zero)
    contentView()?.inputAssistantItem.leadingBarButtonGroups = []
    contentView()?.inputAssistantItem.trailingBarButtonGroups = []
  }
  
  func setupAccessoryView() {
    inputAssistantItem.leadingBarButtonGroups = []
    inputAssistantItem.trailingBarButtonGroups = []
    if let v = _inputAccessoryView as? KBAccessoryView {
      v.isHidden = false
    } else {
      _inputAccessoryView = KBAccessoryView(kbView: _kbView)
      
    }
  }
  
  override var inputAccessoryView: UIView? {
    return _inputAccessoryView
  }
  
  func setupAssistantItem() {
    let proxy = KBProxy(kbView: _kbView)
    let item = UIBarButtonItem(customView: proxy)
    contentView()?.inputAssistantItem.leadingBarButtonGroups = []
    contentView()?.inputAssistantItem.trailingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems: [item], representativeItem: nil)]
  }
  
  func _setupWithKBNotification(notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let kbFrameEnd = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
      let isLocal = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool,
      isLocal // we reconfigure kb only for local notifications
    else {
      if notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool == false {
        self.device?.view?.blur()
      }
      return
    }
    
    var traits       = _kbView.traits
    let mainScreen   = UIScreen.main
    let screenHeight = mainScreen.bounds.height
    let isIPad       = traitCollection.userInterfaceIdiom == .pad
    var isOnScreenKB = kbFrameEnd.size.height > 110
    // External screen kb workaround
    if isOnScreenKB && isIPad && device?.view?.window?.screen !== mainScreen {
       isOnScreenKB = kbFrameEnd.origin.y < screenHeight - 140
    }
    
    let isFloatingKB = isIPad && kbFrameEnd.origin.x > 0 && kbFrameEnd.origin.y > 0
    
    defer {
      traits.isFloatingKB = isFloatingKB
      traits.isHKBAttached = !isOnScreenKB
      _kbView.traits = traits
    }
    
    if traits.isHKBAttached && isOnScreenKB {
      if isIPad {
        if isFloatingKB {
          _kbView.kbDevice = .in6_5
          traits.isPortrait = true
          setupAccessoryView()
        } else {
          setupAssistantItem()
        }
      } else {
        setupAccessoryView()
      }
    } else if !traits.isHKBAttached && !isOnScreenKB {
      _kbView.kbDevice = .detect()
      if _hideSmartKeysWithHKB {
        _removeSmartKeys()
      } else if isIPad {
        setupAssistantItem()
      } else {
        setupAccessoryView()
      }
    } else if !traits.isFloatingKB && isFloatingKB {
      if isFloatingKB {
        _kbView.kbDevice = .in6_5
        traits.isPortrait = true
        setupAccessoryView()
      } else {
        setupAssistantItem()
      }
    } else if traits.isFloatingKB && !isFloatingKB {
      _kbView.kbDevice = .detect()
      _removeSmartKeys()
      setupAssistantItem()
    } else {
      return
    }
    
    DispatchQueue.main.async {
      self.refreshInputViews()
    }
  }

  override func _keyboardDidChangeFrame(_ notification: Notification) {
    
  }
  
  override func _keyboardWillChangeFrame(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let kbFrameEnd = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
      let isLocal = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool
    else {
      return
    }
        
    var bottomInset: CGFloat = 0

    let screenMaxY = UIScreen.main.bounds.size.height
    
    let kbMaxY = kbFrameEnd.maxY
    let kbMinY = kbFrameEnd.minY
    
    if kbMaxY >= screenMaxY {
      bottomInset = screenMaxY - kbMinY
    }
    
    if (bottomInset < 30) {
      bottomInset = 0
    }
    
    if isLocal && traitCollection.userInterfaceIdiom == .pad {
      let isFloating = kbFrameEnd.origin.y > 0 && kbFrameEnd.origin.x > 0 || kbFrameEnd == .zero
      if !_kbView.traits.isFloatingKB && isFloating {
        _kbView.kbDevice = .in6_5
        _kbView.traits.isPortrait = true
        setupAccessoryView()
        DispatchQueue.main.async {
          self.contentView()?.reloadInputViews()
        }
      } else if _kbView.traits.isFloatingKB && !isFloating && !_kbView.traits.isHKBAttached {
        _kbView.kbDevice = .detect()
        _removeSmartKeys()
        setupAssistantItem()
        DispatchQueue.main.async {
          self.contentView()?.reloadInputViews()
        }
      }
      _kbView.traits.isFloatingKB = isFloating
    }

    LayoutManager.updateMainWindowKBBottomInset(bottomInset);
  }
  
  override func _keyboardWillShow(_ notification: Notification) {
    _setupWithKBNotification(notification: notification)
  }
  
  override func _keyboardWillHide(_ notification: Notification) {
//    _setupWithKBNotification(notification: notification)
  }
  
  override func _keyboardDidHide(_ notification: Notification) {
    
  }
  
  override func _keyboardDidShow(_ notification: Notification) {
    _kbView.invalidateIntrinsicContentSize()
    _keyboardWillChangeFrame(notification)
  }

  override func copy(_ sender: Any?) {
    device?.view?.copy(sender)
  }
  
  override func paste(_ sender: Any?) {
    device?.view?.paste(sender)
  }
  
  override func onSelection(_ args: [AnyHashable : Any]) {
    if let dir = args["dir"] as? String, let gran = args["gran"] as? String {
      device?.view?.modifySelection(inDirection: dir, granularity: gran)
    } else if let op = args["command"] as? String {
      switch op {
      case "change": device?.view?.modifySideOfSelection()
      case "copy": copy(self)
      case "paste": device?.view?.pasteSelection(self)
      case "cancel": fallthrough
      default:  device?.view?.cleanSelection()
      }
    }
  }
  
  @objc static let shared = SmarterTermInput()
}


extension SmarterTermInput: TermInput {
  var secureTextEntry: Bool {
    get {
      false
    }
    set(secureTextEntry) {
      
    }
  }
  
}
