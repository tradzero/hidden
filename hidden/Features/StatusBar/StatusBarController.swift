//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

class StatusBarController {
    
    //MARK: - Variables
    private var timer:Timer? = nil
    
    //MARK: - BarItems
        
    // Register fresh names in order: separator, spacers, arrow (left to right).
    // macOS 27 owns saved positions; new spacers cannot be inserted into an old group.
    private let btnExpandCollapse = StatusBarController.makeItem("hiddenbar_expandcollapse", length: NSStatusItem.variableLength)
    private let ordinarySpacers = StatusBarController.makeSpacers("ordinary")
    private let btnSeparate = StatusBarController.makeItem("hiddenbar_separate", length: 1)
    private let alwaysSpacers = StatusBarController.makeSpacers("always")
    private var btnAlwaysHidden: NSStatusItem? = StatusBarController.makeAlwaysItem()

    private static func makeItem(_ name: String, length: CGFloat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: length)
        if #available(macOS 27.0, *) { item.autosaveName = name + "_wide_v1" }
        return item
    }

    private static func makeSpacers(_ section: String) -> [NSStatusItem] {
        guard #available(macOS 27.0, *) else { return [] }
        // Keep the count/names fixed across launches, even when the section is disabled.
        return (0..<6).map { index in
            let item = makeItem("hiddenbar_\(section)_spacer\(index)", length: 0)
            item.button?.isEnabled = false
            return item
        }
    }

    private static func makeAlwaysItem() -> NSStatusItem? {
        guard #available(macOS 27.0, *) else { return nil }
        return makeItem("hiddenbar_terminate", length: 0)
    }

    private func setSpacers(_ spacers: [NSStatusItem], length: CGFloat?) {
        for item in spacers {
            // Hide first when expanding; zero length alone can leave inter-item gaps.
            if length == nil { item.isVisible = false }
            if length != nil { item.isVisible = true }
            item.length = length ?? 0
        }
    }
    
    private var btnHiddenLength: CGFloat = 20
    private var btnHiddenCollapseLength: CGFloat = 2000
    
    private var btnAlwaysHiddenLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
    private var btnAlwaysHiddenEnableExpandCollapseLength: CGFloat = Preferences.alwaysHiddenSectionEnabled ? 2000 : 0
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        // Compare with > rather than == so the state survives updateCollapsedLengths
        // changing btnHiddenCollapseLength while the bar is collapsed (PR #354).
        return usesCalibratedCollapse ? modernCollapsed : self.btnSeparate.length > self.btnHiddenLength
    }
    
    private var isBtnSeparateValidPosition: Bool {
        guard
            let btnExpandCollapseX = self.btnExpandCollapse.button?.getOrigin?.x,
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnExpandCollapseX >= btnSeparateX
        } else {
            return btnExpandCollapseX <= btnSeparateX
        }
    }
    
    private var isBtnAlwaysHiddenValidPosition: Bool {
        if !Preferences.alwaysHiddenSectionEnabled { return true }
        
        guard
            let btnSeparateX = self.btnSeparate.button?.getOrigin?.x,
            let btnAlwaysHiddenX = self.btnAlwaysHidden?.button?.getOrigin?.x
            else {return false}
        
        if Constant.isUsingLTRLanguage {
            return btnSeparateX >= btnAlwaysHiddenX
        } else {
            return btnSeparateX <= btnAlwaysHiddenX
        }
    }
    
    private var isToggle = false

    private var usesCalibratedCollapse: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }
    // User intent is independent of the temporary lengths used by a probe.
    private var modernCollapsed = false
    private var modernLayoutBusy = false
    private var modernLayoutFailed = false
    private var layoutGeneration = 0
    private var ordinaryCachedLength: CGFloat?
    private var alwaysCachedLength: CGFloat?
    private var ordinaryCalibration: CollapseLengthCalibrator?
    private var alwaysCalibration: CollapseLengthCalibrator?

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }

    // The preferences window is an ordinary app window, not in the menu bar, so
    // the mouse-in-menubar guard does not cover it. With "use full menu bar on
    // expanding" on, an auto-collapse deactivates the app and dismisses this
    // window mid-edit (#170, same family as #66/#151). Defer the collapse while
    // it is on screen. isWindowLoaded short-circuits without force-loading the
    // window when preferences were never opened.
    private var isPreferencesWindowVisible: Bool {
        let wc = PreferencesWindowController.shared
        return wc.isWindowLoaded && (wc.window?.isVisible ?? false)
    }
    
    //MARK: - Methods
    init() {
        updateCollapsedLengths()
        setupUI()
        restoreRemovedStatusItems()
        setupAlwayHideStatusBar()
        setupHoverToExpandIfEnabled()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if usesCalibratedCollapse {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(modernEnvironmentChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(modernEnvironmentChanged(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBar()
        }
        
        if Preferences.areSeparatorsHidden {hideSeparators()}
        autoCollapseIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        ordinaryCalibration?.cancel()
        alwaysCalibration?.cancel()
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCollapsed && self.isMouseInMenuBar else {
                self.hoverDwellTimer?.invalidate()
                self.hoverDwellTimer = nil
                return
            }
            // Short dwell so a pointer merely passing through doesn't expand.
            guard self.hoverDwellTimer == nil else { return }
            self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        if usesCalibratedCollapse {
            updateCollapsedLengths()
            scheduleModernRecalibration()
            return
        }
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        let wasCollapsed = isCollapsed
        updateCollapsedLengths()
        if wasCollapsed {
            btnSeparate.length = btnHiddenCollapseLength
            if Preferences.areSeparatorsHidden {
                btnAlwaysHidden?.length = btnAlwaysHiddenEnableExpandCollapseLength
            }
        }
    }

    private func updateCollapsedLengths() {
        if usesCalibratedCollapse {
            btnAlwaysHiddenLength = Preferences.alwaysHiddenSectionEnabled ? 20 : 0
        }
        // The menubar replicates across every attached display, so the collapse
        // length must cover the WIDEST screen, not NSScreen.main (the focused one);
        // sizing from a narrower screen leaks hidden icons on wider displays.
        // frame.width, not visibleFrame: the menubar spans the full frame width.
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        // Preserve the historical bounded request on older systems (PR #354).
        // On macOS 27 this is only the search ceiling, not a claimed layout limit.
        let boundedCollapseLength = max(500, min(screenWidth * 2, 10_000))
        btnHiddenCollapseLength = boundedCollapseLength
        btnAlwaysHiddenEnableExpandCollapseLength = Preferences.alwaysHiddenSectionEnabled ? boundedCollapseLength : 0
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
        }
        let menu = self.getContextMenu()
        btnSeparate.menu = menu

        updateAutoCollapseMenuTitle()
        
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            updateArrowDescription(collapsed: false)
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        if !usesCalibratedCollapse {
            btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse"
            btnSeparate.autosaveName = "hiddenbar_separate"
        }
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        // Accessibility and keyboard activation need not have a mouse-up event.
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseUp || event.type == .rightMouseUp else {
            expandCollapseIfNeeded()
            return
        }
        if event.modifierFlags.contains(.option) {
            showHideSeparatorsAndAlwayHideArea()
        } else if event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            expandCollapseIfNeeded()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        guard let menu = btnSeparate.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }
    
    func showHideSeparatorsAndAlwayHideArea() {
        Preferences.areSeparatorsHidden ? self.showSeparators() : self.hideSeparators()
        
        if self.isCollapsed {self.expandMenubar()}
    }
    
    private func showSeparators() {
        Preferences.areSeparatorsHidden = false
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        self.btnAlwaysHidden?.length = self.btnAlwaysHiddenLength
        if usesCalibratedCollapse { applyModernLayout(collapsed: false) }
    }
    
    private func hideSeparators() {
        guard self.isBtnAlwaysHiddenValidPosition else {return}
        
        Preferences.areSeparatorsHidden = true
        
        if !self.isCollapsed {
            self.btnSeparate.length = self.btnHiddenLength
        }
        if usesCalibratedCollapse {
            applyModernLayout(collapsed: false)
        } else {
            self.btnAlwaysHidden?.length = self.btnAlwaysHiddenEnableExpandCollapseLength
        }
    }
    
    func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    private func collapseMenuBar() {
        guard self.isBtnSeparateValidPosition && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        if usesCalibratedCollapse {
            applyModernLayout(collapsed: true)
            return
        }
        btnSeparate.length = self.btnHiddenCollapseLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.expandImage
            updateArrowDescription(collapsed: true)
        }
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.accessory)
            NSApp.deactivate()
        }
    }
    private func expandMenubar() {
        guard self.isCollapsed else {return}
        if usesCalibratedCollapse {
            applyModernLayout(collapsed: false)
            return
        }
        btnSeparate.length = btnHiddenLength
        if let button = btnExpandCollapse.button {
            button.image = Assets.collapseImage
            updateArrowDescription(collapsed: false)
        }
        autoCollapseIfNeeded()
        
        if Preferences.useFullStatusBarOnExpandEnabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
        }
    }
    
    private func autoCollapseIfNeeded() {
        if usesCalibratedCollapse && (modernLayoutBusy || modernLayoutFailed) { return }
        guard Preferences.isAutoHide else {return}
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    @objc private func modernEnvironmentChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        // A pinned separator edge does not prove that icons remain hidden:
        // a shorter foreground menu can reveal icons without moving that edge.
        scheduleModernRecalibration()
    }

    private func cancelModernCalibration() {
        layoutGeneration += 1
        ordinaryCalibration?.cancel()
        alwaysCalibration?.cancel()
        modernLayoutBusy = false
    }

    private func scheduleModernRecalibration() {
        cancelModernCalibration()
        timer?.invalidate()
        modernLayoutBusy = true
        ordinaryCachedLength = nil
        alwaysCachedLength = nil
        let token = layoutGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.layoutGeneration == token else { return }
            self.applyModernLayout(collapsed: self.modernCollapsed)
        }
    }

    private func geometry(of item: NSStatusItem, anchoredTo anchor: NSStatusItem) -> CollapseLengthCalibrator.Geometry? {
        guard !NSScreen.screens.isEmpty,
              let frame = item.button?.window?.frame,
              let anchorFrame = anchor.button?.window?.frame,
              frame.width > 0, anchorFrame.width > 0 else { return nil }
        let ltr = Constant.isUsingLTRLanguage
        let context = NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: ";") + "|\(ltr)"
        return CollapseLengthCalibrator.Geometry(edge: ltr ? frame.maxX : frame.minX,
                                                anchor: ltr ? anchorFrame.minX : anchorFrame.maxX,
                                                context: context)
    }

    private func makeCalibration(for item: NSStatusItem, anchor: NSStatusItem) -> CollapseLengthCalibrator {
        CollapseLengthCalibrator(read: { [weak self, weak item, weak anchor] in
            guard let self = self, let item = item, let anchor = anchor else { return nil }
            return self.geometry(of: item, anchoredTo: anchor)
        }, write: { [weak item] length in item?.length = length })
    }

    private func updateArrowDescription(collapsed: Bool) {
        let description = (collapsed ? "Show hidden icons" : "Hide icons").localized
        btnExpandCollapse.button?.toolTip = description
        btnExpandCollapse.button?.setAccessibilityLabel(description)
    }

    private func updateModernAppearance() {
        // AppKit 27 can reset length when the image is assigned, even to the same
        // value. Do not invalidate a successful probe while refreshing the arrow.
        let separatorImage = modernCollapsed ? nil : imgIconLine
        if btnSeparate.button?.image !== separatorImage { btnSeparate.button?.image = separatorImage }
        let alwaysImage = Preferences.areSeparatorsHidden ? nil : imgIconLine
        if btnAlwaysHidden?.button?.image !== alwaysImage { btnAlwaysHidden?.button?.image = alwaysImage }
        updateArrowDescription(collapsed: modernCollapsed)
        let arrowImage = modernCollapsed ? Assets.expandImage : Assets.collapseImage
        if btnExpandCollapse.button?.image !== arrowImage { btnExpandCollapse.button?.image = arrowImage }
        if Preferences.useFullStatusBarOnExpandEnabled {
            let policy: NSApplication.ActivationPolicy = modernCollapsed ? .accessory : .regular
            if NSApp.activationPolicy() != policy {
                NSApp.setActivationPolicy(policy)
                if modernCollapsed { NSApp.deactivate() }
                else { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        if let notice = btnSeparate.menu?.item(withTag: 27) {
            notice.isHidden = !modernLayoutFailed
        }
    }

    private func applyModernLayout(collapsed: Bool) {
        cancelModernCalibration()
        timer?.invalidate()
        modernCollapsed = collapsed
        modernLayoutBusy = true
        modernLayoutFailed = false
        let token = layoutGeneration
        setSpacers(ordinarySpacers, length: nil)
        btnSeparate.length = btnHiddenLength
        updateModernAppearance()

        // Calibrate the always-hidden item independently with the ordinary section
        // expanded. Its available space is different, so never borrow the other value.
        if Preferences.alwaysHiddenSectionEnabled && Preferences.areSeparatorsHidden,
           let item = btnAlwaysHidden {
            if let length = alwaysCachedLength, length == item.length,
               alwaysSpacers.allSatisfy({ $0.isVisible && $0.length == length }) {
                // Keep the established always-hidden block during an ordinary toggle.
                // App/display changes explicitly invalidate this cache.
                applyModernOrdinarySection(token: token)
            } else {
                calibrateAlwaysHidden(item, token: token)
            }
        } else {
            setSpacers(alwaysSpacers, length: nil)
            btnAlwaysHidden?.length = btnAlwaysHiddenLength
            applyModernOrdinarySection(token: token)
        }
    }

    private func calibrateAlwaysHidden(_ item: NSStatusItem, token: Int) {
        setSpacers(alwaysSpacers, length: nil)
        let calibration = makeCalibration(for: item, anchor: btnSeparate)
        alwaysCalibration = calibration
        calibration.start(expanded: btnAlwaysHiddenLength, upperBound: btnHiddenCollapseLength,
                          cached: alwaysCachedLength) { [weak self] result in
            guard let self = self, self.layoutGeneration == token else { return }
            if case .applied(let length) = result {
                self.alwaysCachedLength = length
                self.setSpacers(self.alwaysSpacers, length: length)
                NSLog("CollapseCalibration: always-hidden applied \(length)pt")
            } else {
                self.alwaysCachedLength = nil
                item.length = self.btnAlwaysHiddenLength
                self.modernLayoutFailed = true
            }
            self.applyModernOrdinarySection(token: token)
        }
    }

    private func applyModernOrdinarySection(token: Int) {
        guard layoutGeneration == token else { return }
        guard modernCollapsed else {
            modernLayoutBusy = false
            updateModernAppearance()
            autoCollapseIfNeeded()
            return
        }
        let calibration = makeCalibration(for: btnSeparate, anchor: btnExpandCollapse)
        ordinaryCalibration = calibration
        calibration.start(expanded: btnHiddenLength, upperBound: btnHiddenCollapseLength,
                          cached: ordinaryCachedLength) { [weak self] result in
            guard let self = self, self.layoutGeneration == token else { return }
            self.modernLayoutBusy = false
            if case .applied(let length) = result {
                self.ordinaryCachedLength = length
                self.setSpacers(self.ordinarySpacers, length: length)
                NSLog("CollapseCalibration: ordinary applied \(length)pt")
            } else {
                self.ordinaryCachedLength = nil
                self.btnSeparate.length = self.btnHiddenLength
                self.modernCollapsed = false
                self.modernLayoutFailed = true
                NSLog("CollapseCalibration: no stable collapse; restored expanded section")
            }
            self.updateModernAppearance()
        }
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers.
            if self.isMouseInMenuBar || self.isPreferencesWindowVisible {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar()
            }
        }
    }
    
    private func getContextMenu() -> NSMenu {
        let menu = NSMenu()
        
        let prefItem = NSMenuItem(title: "Preferences...".localized, action: #selector(openPreferenceViewControllerIfNeeded), keyEquivalent: "P")
        prefItem.target = self
        menu.addItem(prefItem)
        
        let toggleAutoHideItem = NSMenuItem(title: "Toggle Auto Collapse".localized, action: #selector(toggleAutoHide), keyEquivalent: "t")
        toggleAutoHideItem.target = self
        toggleAutoHideItem.tag = 1
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        menu.addItem(toggleAutoHideItem)

        if usesCalibratedCollapse {
            let notice = NSMenuItem(title: "Hiding unavailable in the current layout".localized, action: nil, keyEquivalent: "")
            notice.tag = 27
            notice.isHidden = true
            menu.addItem(notice)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        return menu
    }
    
    private func updateAutoCollapseMenuTitle() {
        guard let toggleAutoHideItem = btnSeparate.menu?.item(withTag: 1) else { return }
        if Preferences.isAutoHide {
            toggleAutoHideItem.title = "Disable Auto Collapse".localized
        } else {
            toggleAutoHideItem.title = "Enable Auto Collapse".localized
        }
    }
    
    @objc func updateAutoHide() {
        updateAutoCollapseMenuTitle()
        autoCollapseIfNeeded()
    }
    
    @objc func openPreferenceViewControllerIfNeeded() {
        Util.showPrefWindow()
    }
    
    @objc func toggleAutoHide() {
        Preferences.isAutoHide.toggle()
    }
}


//MARK: - Alway hide feature
extension StatusBarController {
    private func setupAlwayHideStatusBar() {
        NotificationCenter.default.addObserver(self, selector: #selector(toggleStatusBarIfNeeded), name: .alwayHideToggle, object: nil)
        toggleStatusBarIfNeeded()
    }
    @objc private func toggleStatusBarIfNeeded() {
        if usesCalibratedCollapse { cancelModernCalibration() }
        updateCollapsedLengths()

        if usesCalibratedCollapse {
            // Retain the registered slot while disabled, including across launches.
            btnAlwaysHidden?.isVisible = Preferences.alwaysHiddenSectionEnabled
            if let button = btnAlwaysHidden?.button {
                if button.image !== imgIconLine { button.image = imgIconLine }
                button.appearsDisabled = true
            }
            setSpacers(alwaysSpacers, length: nil)
        } else if Preferences.alwaysHiddenSectionEnabled {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = NSStatusBar.system.statusItem(withLength: btnAlwaysHiddenLength)
            if let button = btnAlwaysHidden?.button {
                button.image = self.imgIconLine
                button.appearsDisabled = true
            }
            self.btnAlwaysHidden?.autosaveName = "hiddenbar_terminate"
            self.btnAlwaysHidden?.isVisible = true
        } else {
            if let existing = self.btnAlwaysHidden {
                NSStatusBar.system.removeStatusItem(existing)
            }
            self.btnAlwaysHidden = nil
        }
        if usesCalibratedCollapse {
            alwaysCachedLength = nil
            ordinaryCachedLength = nil
            applyModernLayout(collapsed: modernCollapsed)
        }
    }
}
