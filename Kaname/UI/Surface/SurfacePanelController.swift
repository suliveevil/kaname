import AppKit
import SwiftUI

final class SurfacePanel: NSPanel {
    /// Only the search palette may become key/mouse focus; the shortcut panel never does.
    var becomesKey = false

    override var canBecomeKey: Bool { becomesKey }
    override var canBecomeMain: Bool { false }
}

/// One window for both surfaces.
///
/// The shortcut panel and the search palette are mutually exclusive *and* share a single
/// NSPanel: switching swaps the hosting content, the size and whether the window may take
/// keyboard focus. There is never a second floating window.
///
/// Conforms to `PanelPresenting` (`Core/Ports/PresentationPorts.swift`) by having the same
/// method names: the engine drives this window through that protocol, and does not know it
/// exists.
@MainActor
final class SurfacePanelController: PanelPresenting {
    enum Mode {
        case hidden
        case panel
        case search
    }

    private let engine: ShortcutEngine
    private let panel: SurfacePanel

    private(set) var mode: Mode = .hidden
    /// Cocoa-coordinate snapshots of the anchor window and the focused element, refreshed
    /// off the main thread when the front app changes. Key presses only read these; they
    /// never call the AX API themselves. The frames and their pid travel together so a
    /// snapshot can be dropped as a whole when the space or the display changes.
    private var anchor = PanelAnchorCache()
    /// Observed for the controller's lifetime; it lives as long as the app, so there is no
    /// deinit to remove them.
    private var spaceChangeObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var lastPanelSettings: AppSettingsSnapshot?
    private var geometryTask: Task<Void, Never>?
    private var isRefreshingGeometry = false
    private var outsideClickMonitor: Any?
    private var searchKeyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var contentInstalled = false

    /// The window's Space and application membership.
    ///
    /// Three separate declarations are needed for a floating panel that must appear over
    /// another app's native full-screen Space: `.canJoinAllSpaces` covers every desktop,
    /// `.canJoinAllApplications` (macOS 13+) lets it join another app's window set — which
    /// is what a native full-screen Space is — and `.fullScreenAuxiliary` allows it beside
    /// the full-screen window. AppKit's header names floating windows and system overlays
    /// as the intended users of `.canJoinAllApplications`.
    ///
    /// `.stationary` is deliberately absent: AppKit defines it as a desktop-like window
    /// ("unaffected by exposé, stays visible and stationary"), which holds a window on the
    /// Space it was born on. A level above `.normal` already gets the `.transient`
    /// behaviour a floating panel needs.
    private static let spaceMembership: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle
    ]

    /// `SpaceRescanGate` and `FocusRescanGate` both treat 0.75 s as one Space-switch
    /// episode; the panel uses the same window for its post-switch re-layout.
    private static let spaceSettleInterval: TimeInterval = 0.75

    /// The last Space-change notification. Frames read during the switch animation belong
    /// to the Space the user just left, so the panel is laid out again once it settles.
    private var lastSpaceChangeAt: Date?
    /// The one deferred post-switch re-layout; cancelled when a surface closes.
    private var settleWork: DispatchWorkItem?
    /// Limits the off-Space self-heal to one attempt per panel session.
    private var didAttemptReanchor = false

    init(engine: ShortcutEngine) {
        self.engine = engine
        panel = SurfacePanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // A native full-screen Space belongs to another process's window set, so Space
        // membership alone is not enough: see `spaceMembership` above. The WindowServer
        // still orders that Space's windows above anything at `.floating`, so the level
        // stays static and aligned with `HUDPanelController` — macOS has no public "is this
        // Space fullscreen" query, and Space-change notifications are an invalidation signal
        // only (see `spaceChangeObserver` below), never a state input. `.statusBar` (25) is
        // far below `popUpMenuWindow` (101), so `PopupGate.menuPresent()` stays meaningful.
        panel.level = .statusBar
        panel.collectionBehavior = Self.spaceMembership
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        // A space or display change moves windows the cached frames were read against, so
        // the snapshot must be read again on the next present instead of placing the panel
        // where the front window used to be.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastSpaceChangeAt = Date()
                self?.cancelSettleWork()
                self?.invalidateAnchorGeometry()
            }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateAnchorGeometry() }
        }
    }

    var isVisible: Bool { mode != .hidden }

    /// The app that was frontmost before the search palette took focus.
    var searchTargetApplication: NSRunningApplication? { previousApp }

    /// What the palette's window is sending keys to.
    ///
    /// A focused `TextField` is served by its field editor — an `NSTextView` — which is what
    /// `/` checks before deciding whether it is a character or the way back to the panel.
    /// Exposed as a string so a log line can answer "why did `/` do that" without a debugger.
    var keyFocusDescription: String {
        let responder = panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let typing = panel.firstResponder is NSTextView
        return "key=\(panel.isKeyWindow) active=\(NSApp.isActive) first=\(responder) typing=\(typing)"
    }

    // MARK: - Shortcut panel

    func presentPanel(state: PanelState, settings: AppSettingsSnapshot) {
        guard state.isVisible else {
            cancelSettleWork()
            closePanel()
            return
        }

        ensureContent()
        let isOpening = mode != .panel
        if isOpening {
            switchToPanel()
            didAttemptReanchor = false
        }

        lastPanelSettings = settings
        let pid = engine.frontmostProcessIdentifier
        // A new front app — or a snapshot cleared by a space/display change — invalidates
        // both frames. Read the replacements in the background and cover the whole visible
        // frame in the meantime: the previous app's window would put the panel somewhere
        // meaningless, and a shrunken guess would leave the new window partly uncovered
        // until the read returns.
        if anchor.beginRead(pid: pid) {
            refreshGeometry(for: pid)
        }

        drawPanel(state: state, settings: settings)
        if isOpening {
            // The authoritative reading is the one taken a run loop later, not the
            // same-run-loop value in the debug line above.
            verifyActiveSpace()
            // A trigger inside a Space-switch animation reads frames, the front app and the
            // menu bar from a transitional state. Show the panel at once — holding it back
            // would swallow the user's keys with nothing on screen — but lay it out again
            // once the switch settles.
            if let remaining = spaceSettleRemaining() {
                scheduleSettleReLayout(after: remaining)
            }
        }
    }

    /// Sizes, places and orders the shared window. Called on every repaint and once more at
    /// the end of a Space-switch episode.
    private func drawPanel(state: PanelState, settings: AppSettingsSnapshot) {
        let screen = targetScreen()
        let size = panelSize(for: state, settings: settings, screen: screen)
        panel.setContentSize(size)
        let frame = panelFrame(size: size, settings: settings, screen: screen)
        // Every keystroke rebuilds the page, but the frame usually does not move. Skipping
        // an identical `setFrame` avoids a whole-window redraw per key. The comparison is
        // the full rect on purpose: with `besideWindow` the size stays the same while the
        // origin follows the anchor window, and a size-only check would leave the panel
        // behind the app it was meant to sit next to.
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        orderFrontOnActiveSpace()
        // "The panel did not open" and "the panel opened where the user cannot see it" look
        // identical from the outside; this line tells them apart. Its `onActiveSpace` is a
        // same-run-loop reading — `verifyActiveSpace()` is the one the PASS check uses.
        Diag.debug(.ui, """
            panel ordered front \(Int(size.width))x\(Int(size.height)) at \
            \(Int(panel.frame.minX)),\(Int(panel.frame.minY)) visible=\(panel.isVisible) \
            onActiveSpace=\(panel.isOnActiveSpace) level=\(panel.level.rawValue) \
            behavior=\(panel.collectionBehavior.rawValue)
            """)
        installOutsideClickMonitor()
        // Armed every time the panel is drawn, because its frame moves with the list: the
        // tap has to know where the panel is before it can tell a click on the panel from a
        // click past it.
        engine.updateOutsideMouseSwallow(
            panelFrame: WindowGeometry.cgRect(fromCocoa: panel.frame),
            appWindowFrame: anchor.windowFrame.map(WindowGeometry.cgRect(fromCocoa:))
        )
    }

    /// Re-anchors the one reused window on the Space the user is looking at.
    ///
    /// WindowServer evaluates a window's Space membership when the window is ordered in.
    /// This window lives for the whole app lifetime, so ordering it front after a switch to
    /// a native full-screen Space can leave it on the desktop it was last shown on. A window
    /// still visible on an inactive Space is taken off screen first so the membership
    /// declaration gets a fresh evaluation; a first open of a hidden window has that fresh
    /// evaluation already, and `verifyActiveSpace()` handles the case where it does not stick.
    ///
    /// UNVERIFIED FALLBACK (2026-11-16): the field test that validated `spaceMembership`
    /// (19 panel sessions, 222 redraws, WorkBuddy and Safari in native full-screen Spaces,
    /// zero `onActiveSpace=false` readings) never entered this branch — not one
    /// `panel ordered out` line was logged. The corrected declaration alone was sufficient.
    /// This re-anchoring is deliberately retained as a defensive path for future
    /// WindowServer behaviour, but it has no runtime evidence behind it and must not be
    /// described as part of the verified fix.
    private func orderFrontOnActiveSpace() {
        if panel.isVisible, !panel.isOnActiveSpace {
            panel.orderOut(nil)
            Diag.debug(.ui, "panel ordered out: it was on an inactive Space")
        }
        panel.collectionBehavior = Self.spaceMembership
        panel.orderFrontRegardless()
    }

    /// Reads `isOnActiveSpace` one run loop after the order-front, when WindowServer has
    /// re-evaluated membership. A same-run-loop reading can be a transient value; this is
    /// the authoritative one. A failure gets exactly one re-parenting attempt per session,
    /// using the `.moveToActiveSpace` path proven by `SettingsWindowController`.
    ///
    /// UNVERIFIED FALLBACK (2026-11-16): the same field test emitted zero
    /// `panel off active Space` warnings, so neither the one-shot `.moveToActiveSpace`
    /// re-parenting nor either post-recheck outcome executed. Kept for the case where the
    /// collection-behaviour declaration stops being enough; treat its success and failure
    /// branches, and `didAttemptReanchor`, as untested code.
    private func verifyActiveSpace() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == .panel, self.panel.isVisible,
                  !self.panel.isOnActiveSpace else { return }
            guard !self.didAttemptReanchor else {
                Diag.warning(.ui, "panel off active Space after re-anchor onActiveSpace=false")
                return
            }
            self.didAttemptReanchor = true
            Diag.warning(.ui, "panel off active Space; re-anchoring once")
            self.panel.orderOut(nil)
            // `.moveToActiveSpace` only applies while the window is off screen. Keep the
            // cross-app and full-screen bits so the panel still reaches another app's Space.
            self.panel.collectionBehavior = [
                .moveToActiveSpace, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle
            ]
            self.panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mode == .panel else { return }
                if self.panel.isOnActiveSpace {
                    Diag.info(.ui, "panel re-anchored on active Space")
                } else {
                    Diag.warning(.ui, "panel still off active Space onActiveSpace=false")
                }
            }
        }
    }

    /// How long until the Space switch that just happened can be treated as settled; nil
    /// outside that window.
    private func spaceSettleRemaining() -> TimeInterval? {
        guard let changed = lastSpaceChangeAt else { return nil }
        let remaining = Self.spaceSettleInterval - Date().timeIntervalSince(changed)
        return remaining > 0 ? remaining : nil
    }

    private func scheduleSettleReLayout(after delay: TimeInterval) {
        cancelSettleWork()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.settleWork = nil
            self.settlePanel()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSettleWork() {
        settleWork?.cancel()
        settleWork = nil
    }

    /// Re-lays the panel out after the switch has settled, from frames and an anchor read on
    /// the new Space rather than the transitional ones the trigger saw.
    private func settlePanel() {
        guard mode == .panel, let settings = lastPanelSettings else { return }
        let screen = targetScreen()
        let size = panelSize(for: engine.state.panel, settings: settings, screen: screen)
        panel.setContentSize(size)
        let frame = panelFrame(size: size, settings: settings, screen: screen)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        // Do not order front again: a re-anchor may already have put `.moveToActiveSpace` on
        // the window, and re-declaring the cross-Space behaviour here would undo it. This
        // reading is taken once the switch has settled, so it is the authoritative verdict.
        verifyActiveSpace()
        Diag.info(.ui, "Space settled: panel re-laid out onActiveSpace=\(panel.isOnActiveSpace)")
        engine.updateOutsideMouseSwallow(
            panelFrame: WindowGeometry.cgRect(fromCocoa: panel.frame),
            appWindowFrame: anchor.windowFrame.map(WindowGeometry.cgRect(fromCocoa:))
        )
    }

    func closePanel() {
        guard mode == .panel else { return }
        hide()
    }

    /// Reads the anchor/floating-element frames in the background and re-lays the panel out
    /// once they arrive. The content is swapped by `setContentSize` only, never rebuilt, so it
    /// does not flash or reorder; the frame settles onto the window that was just read.
    private func refreshGeometry(for pid: pid_t) {
        guard !isRefreshingGeometry else { return }
        isRefreshingGeometry = true
        geometryTask = Task { [weak self] in
            let snapshot = await PanelGeometryReader.read(pid: pid)
            guard let self else { return }
            self.isRefreshingGeometry = false
            guard self.anchor.apply(
                pid: pid,
                windowFrame: snapshot.windowFrame.map(WindowGeometry.cocoaRect(fromAX:)),
                focusedElementFrame: snapshot.focusedElementFrame.map(WindowGeometry.cocoaRect(fromAX:))
            ) else {
                // The front app — or the snapshot itself — changed while this read was in
                // flight. Only read again when there is a pid to read for.
                if self.anchor.pid != 0 {
                    self.refreshGeometry(for: self.anchor.pid)
                }
                return
            }
            guard self.mode != .hidden else { return }
            switch self.mode {
            case .panel:
                guard let settings = self.lastPanelSettings else { return }
                // The frame that arrived may be the first one for this app, so the panel was
                // drawn from the fallback size. Recompute it here as well: repositioning the
                // fallback left a tall window uncovered until the next `presentPanel`.
                let screen = self.targetScreen()
                let size = self.panelSize(for: self.engine.state.panel, settings: settings, screen: screen)
                self.panel.setContentSize(size)
                self.panel.setFrame(
                    self.panelFrame(size: size, settings: settings, screen: screen),
                    display: true
                )
                self.engine.updateOutsideMouseSwallow(
                    panelFrame: WindowGeometry.cgRect(fromCocoa: self.panel.frame),
                    appWindowFrame: self.anchor.windowFrame.map(WindowGeometry.cgRect(fromCocoa:))
                )
            case .search:
                // The frame arrived after the palette was placed from the fallback; move it
                // onto the window now that the real frame is known.
                guard let visible = self.targetScreen()?.visibleFrame else { return }
                let size = OverlayPlacement.searchSize(windowFrame: self.anchor.windowFrame, visible: visible)
                self.panel.setContentSize(size)
                self.panel.setFrame(
                    OverlayPlacement.searchFrame(windowFrame: self.anchor.windowFrame, visible: visible, size: size),
                    display: true
                )
            case .hidden:
                break
            }
        }
    }

    // MARK: - Search palette

    func presentSearch() {
        cancelSettleWork()
        ensureContent()
        if mode != .search {
            if mode == .hidden {
                previousApp = NSWorkspace.shared.frontmostApplication
            }
            switchToSearch()
        }
        // Read the target pid before `NSApp.activate()`: afterwards the frontmost app is
        // Kaname itself, and its window frame is not what the palette should centre on.
        let pid = previousApp.map(\.processIdentifier) ?? engine.frontmostProcessIdentifier
        if anchor.beginRead(pid: pid) {
            refreshGeometry(for: pid)
        }
        let screen = targetScreen()
        let size: CGSize
        let frame: CGRect
        if let visible = screen?.visibleFrame {
            size = OverlayPlacement.searchSize(windowFrame: anchor.windowFrame, visible: visible)
            frame = OverlayPlacement.searchFrame(windowFrame: anchor.windowFrame, visible: visible, size: size)
        } else {
            size = CGSize(width: OverlayPlacement.searchWidth, height: OverlayPlacement.searchMinHeight)
            frame = CGRect(origin: .zero, size: size)
        }
        panel.setContentSize(size)
        panel.setFrame(frame, display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installSearchKeyMonitor()
        installOutsideClickMonitor()
    }

    func closeSearch() {
        guard mode == .search else { return }
        hide()
        restorePreviousAppIfNeeded()
    }

    func close() {
        switch mode {
        case .panel:
            closePanel()
        case .search:
            closeSearch()
        case .hidden:
            break
        }
    }

    // MARK: - Mode switching

    private func switchToPanel() {
        removeSearchKeyMonitor()
        if panel.isKeyWindow {
            panel.resignKey()
        }
        restorePreviousAppIfNeeded()
        mode = .panel
        panel.becomesKey = false
    }

    private func switchToSearch() {
        mode = .search
        panel.becomesKey = true
    }

    private func ensureContent() {
        guard !contentInstalled else { return }
        contentInstalled = true
        panel.contentView = NSHostingView(
            rootView: OverlayView()
                .environmentObject(engine)
                .environment(engine.state)
                .environmentObject(engine.settingsStore)
                .environmentObject(engine.localization)
                .environmentObject(engine.usageStore)
        )
    }

    private func hide() {
        let closingMode = mode
        cancelSettleWork()
        mode = .hidden
        removeSearchKeyMonitor()
        removeOutsideClickMonitor()
        // Nothing is showing, so nothing is left to protect the app behind from.
        engine.updateOutsideMouseSwallow(panelFrame: nil, appWindowFrame: nil)
        // A surface dismissed while off the active Space is a different failure from one
        // the user simply left the app from. Record the reading before ordering the window
        // out, while it still has a Space to be read against.
        Diag.debug(.ui, """
            surface hidden from \(String(describing: closingMode)) \
            onActiveSpace=\(panel.isOnActiveSpace)
            """)
        panel.orderOut(nil)
        invalidateAnchorGeometry()
    }

    /// Drops the cached frames and any read that is still in flight, so the next present
    /// reads against the new space or display instead of reusing a stale window frame.
    private func invalidateAnchorGeometry() {
        geometryTask?.cancel()
        geometryTask = nil
        isRefreshingGeometry = false
        anchor.invalidate()
    }

    private func restorePreviousAppIfNeeded() {
        guard NSApp.isActive, let previousApp, !previousApp.isTerminated else {
            self.previousApp = nil
            return
        }
        previousApp.activate()
        self.previousApp = nil
    }

    // MARK: - Search keyboard handling

    private func installSearchKeyMonitor() {
        guard searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated {
                guard let self else { return }
                // While an input method is composing, Return commits candidates, arrows move
                // the candidate window and Escape cancels it. None of those belong to the
                // palette, so let the text field see the event untouched.
                if TextComposition.isComposing(in: self.panel) { return }
                // The key-by-key decision is pure and tested (`SearchKeyRouter`); here we only
                // run the action it returns.
                let modifiers = ModifierSet.from(flags: event.modifierFlags)
                let isQueryEmpty = self.engine.state.search.query
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                switch SearchKeyRouter.action(
                    keyCode: event.keyCode,
                    modifiers: modifiers,
                    isQueryEmpty: isQueryEmpty,
                    characters: event.characters
                ) {
                case .moveSelection(let delta):
                    self.engine.moveSearchSelection(delta)
                    handled = true
                case .close:
                    self.engine.hideSearch()
                    handled = true
                case .returnToPanel:
                    self.engine.returnToPanelFromSearch()
                    handled = true
                case .passThrough:
                    break
                }
            }
            return handled ? nil : event
        }
    }

    private func removeSearchKeyMonitor() {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
            self.searchKeyMonitor = nil
        }
    }

    // MARK: - Outside clicks

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    switch self.mode {
                    case .panel: self.engine.dismissPanel()
                    case .search: self.engine.hideSearch()
                    case .hidden: break
                    }
                }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: - Placement

    /// The screen the panel will land on, resolved the same way `presentPanel` resolves it.
    func targetVisibleFrame() -> CGRect? {
        targetScreen()?.visibleFrame
    }

    private func targetScreen() -> NSScreen? {
        if let anchorFrame = anchor.windowFrame,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) {
            return screen
        }
        return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The panel's frame size for a given state, including the cover-height correction.
    private func panelSize(for state: PanelState, settings: AppSettingsSnapshot, screen: NSScreen?) -> CGSize {
        let natural = OverlayMetrics.size(for: state, settings: settings)
        var size = placementSize(natural: natural, settings: settings, screen: screen)
        if settings.panelPlacement == .coverWindow {
            // A wider panel fits more columns, so the content height follows the final width —
            // but the cover height must survive that. Taking the larger of the two keeps the
            // window covered; a panel that shrank to its content stopped covering a tall window.
            let contentHeight = OverlayMetrics.size(for: state, settings: settings, width: size.width).height
            size.height = OverlayPlacement.coveredHeight(
                contentHeight: contentHeight,
                coverHeight: size.height,
                limit: screen?.visibleFrame.height ?? size.height
            )
        }
        return size
    }

    private func placementSize(natural: CGSize, settings: AppSettingsSnapshot, screen: NSScreen?) -> CGSize {
        guard let screen else { return natural }
        let visible = screen.visibleFrame
        switch settings.panelPlacement {
        case .fillScreen:
            return OverlayPlacement.fillScreenFrame(
                visible: visible,
                safeAreaTop: screen.safeAreaInsets.top
            ).size
        case .fixedSize:
            return CGSize(
                width: min(CGFloat(settings.fixedPanelWidth), visible.width),
                height: min(CGFloat(settings.fixedPanelHeight), visible.height)
            )
        case .coverWindow:
            // The front window's frame arrives asynchronously, so the first frame after an
            // app switch has no window to cover. A shrunken guess left the window half
            // exposed; the visible frame covers every window, so start there and settle
            // onto the window once its frame is known.
            return OverlayPlacement.coverSize(
                windowFrame: anchor.windowFrame,
                visible: visible,
                natural: natural
            )
        case .besideWindow:
            return natural
        }
    }

    private func panelFrame(size: CGSize, settings: AppSettingsSnapshot, screen: NSScreen?) -> CGRect {
        guard let screen else { return CGRect(origin: .zero, size: size) }
        let visible = screen.visibleFrame
        switch settings.panelPlacement {
        case .fillScreen:
            return OverlayPlacement.fillScreenFrame(
                visible: visible,
                safeAreaTop: screen.safeAreaInsets.top
            )
        case .fixedSize, .coverWindow:
            return OverlayPlacement.clampedTop(
                OverlayPlacement.containedFrame(
                    CGRect(
                        x: visible.midX - size.width / 2,
                        y: visible.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    in: visible
                ),
                in: visible,
                safeAreaTop: screen.safeAreaInsets.top
            )
        case .besideWindow:
            return besideWindowFrame(size: size, screen: screen)
        }
    }

    private func besideWindowFrame(size: CGSize, screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        guard let anchorFrame = anchor.windowFrame else {
            return clamp(
                CGRect(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16, width: size.width, height: size.height),
                to: visible
            )
        }

        var candidate = CGRect(
            x: anchorFrame.maxX + 12,
            y: anchorFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if candidate.maxX > visible.maxX - 8 {
            candidate.origin.x = anchorFrame.minX - size.width - 12
        }
        if candidate.minX < visible.minX + 8 {
            candidate.origin.x = anchorFrame.minX + 16
            candidate.origin.y = anchorFrame.minY - size.height - 12
        }
        candidate = clamp(candidate, to: visible)

        if let focused = anchor.focusedElementFrame,
           focused.width > 1,
           candidate.intersects(focused) {
            var alternative = candidate
            alternative.origin.y = anchorFrame.minY - size.height - 12
            if alternative.minY >= visible.minY + 8, !alternative.intersects(focused) {
                return clamp(alternative, to: visible)
            }
            alternative.origin.y = visible.minY + 8
            if !alternative.intersects(focused) {
                return clamp(alternative, to: visible)
            }
        }
        return candidate
    }

    private func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        OverlayPlacement.containedFrame(rect, in: bounds)
    }

    private func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
