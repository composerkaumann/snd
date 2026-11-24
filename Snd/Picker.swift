import AppKit
import UserNotifications

@MainActor
private final class Picker: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate, UNUserNotificationCenterDelegate {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let footer = NSTextField(wrappingLabelWithString: "")
    private let outputMenuItem = NSMenuItem()
    private let languageMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem(
        title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
    )
    private var outputs: [AudioOutput] = []
    private var current: UInt32?
    private var keyMonitor: Any?
    private var isFinishingSelection = false

    func installMenu(on app: NSApplication) {
        let menuBar = NSMenu()
        let appMenuItem = NSMenuItem()
        menuBar.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Snd")
        appMenuItem.submenu = appMenu
        let languageMenu = NSMenu()
        for language in SndLanguage.allCases {
            let item = languageMenu.addItem(withTitle: "", action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
        }
        languageMenuItem.submenu = languageMenu
        appMenu.addItem(languageMenuItem)
        appMenu.addItem(.separator())
        quitMenuItem.target = app
        appMenu.addItem(quitMenuItem)

        let outputMenu = NSMenu()
        outputMenu.delegate = self
        menuBar.addItem(outputMenuItem)
        outputMenuItem.submenu = outputMenu
        updateLocalizedLabels()
        app.mainMenu = menuBar
    }

    private func updateLocalizedLabels() {
        let outputTitle = SndLanguage.text("Sound Output")
        window.title = outputTitle
        outputMenuItem.title = outputTitle
        outputMenuItem.submenu?.title = outputTitle
        table.setAccessibilityLabel(SndLanguage.text("Available sound outputs"))

        let languageTitle = SndLanguage.text("Language")
        languageMenuItem.title = languageTitle
        languageMenuItem.submenu?.title = languageTitle
        for (item, language) in zip(languageMenuItem.submenu?.items ?? [], SndLanguage.allCases) {
            item.title = language.menuTitle
            item.state = language == SndLanguage.preference ? .on : .off
        }
        quitMenuItem.title = SndLanguage.text("Quit Snd")
    }

    @objc private func selectLanguage(_ item: NSMenuItem) {
        guard let code = item.representedObject as? String,
              let language = SndLanguage(rawValue: code) else { return }
        SndLanguage.preference = language
        updateLocalizedLabels()
        reloadOutputs()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        reloadOutputs()
        menu.removeAllItems()
        if outputs.isEmpty {
            menu.addItem(withTitle: footer.stringValue, action: nil, keyEquivalent: "")
            return
        }

        for (index, output) in outputs.enumerated() {
            let item = menu.addItem(
                withTitle: "\(index + 1). \(output.name)",
                action: #selector(selectMenuOutput(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = output
            item.state = output.id == current ? .on : .off
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureWindow()
        UNUserNotificationCenter.current().delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === window else { return event }
            return handlePickerKey(event) ? nil : event
        }
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !isFinishingSelection { show() }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window.isVisible { focusWindow() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    private func configureWindow() {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("output"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = 32
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        let click = NSClickGestureRecognizer(target: self, action: #selector(selectClickedRow(_:)))
        table.addGestureRecognizer(click)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 12, right: 14)

        let content = NSView()
        window.contentView = content
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            footer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    private func show() {
        reloadOutputs()
        let visibleRows = max(1, min(outputs.count, 9))
        window.setContentSize(NSSize(width: 430, height: CGFloat(visibleRows * 35 + 56)))
        window.center()
        focusWindow()
        NSApp.activate()
    }

    private func focusWindow() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
    }

    private func reloadOutputs(message: String? = nil) {
        do {
            outputs = try AudioOutputs.list()
            current = try? AudioOutputs.current()
            let lastShortcut = min(outputs.count, 9)
            let keys = lastShortcut == 1 ? "1" : "1–\(lastShortcut)"
            let hint = SndLanguage.text("↑/↓ then Return or %@ to select · Esc to close", keys)
            footer.stringValue = message ?? (outputs.isEmpty ? SndLanguage.text("No sound outputs available.") : hint)
        } catch {
            outputs = []
            footer.stringValue = error.localizedDescription
        }
        table.reloadData()
        if let index = outputs.firstIndex(where: { $0.id == current }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        outputs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let output = outputs[row]
        let name = NSTextField(labelWithString: "\(row + 1). \(output.name)")
        name.lineBreakMode = .byTruncatingTail
        name.toolTip = output.name
        let cell = NSTableCellView()
        cell.addSubview(name)
        cell.textField = name
        name.translatesAutoresizingMaskIntoConstraints = false
        let isCurrent = output.id == current
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: isCurrent ? -80 : -8),
        ])
        if isCurrent {
            let status = NSTextField(labelWithString: SndLanguage.text("In Use"))
            status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            status.textColor = .secondaryLabelColor
            cell.addSubview(status)
            status.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                status.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                status.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    private func handlePickerKey(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers
        if event.keyCode == 53 || key == "\u{1b}" {
            if !event.isARepeat { window.close() }
            return true
        }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { return false }

        if event.keyCode == 36 || event.keyCode == 76 || key == "\r" || key == "\u{3}" {
            if !event.isARepeat { selectRow(table.selectedRow) }
            return true
        }
        if let key, let number = Int(key), (1...9).contains(number) {
            if !event.isARepeat { selectRow(number - 1) }
            return true
        }
        return false
    }

    @objc private func selectClickedRow(_ gesture: NSClickGestureRecognizer) {
        selectRow(table.row(at: gesture.location(in: table)))
    }

    @objc private func selectMenuOutput(_ item: NSMenuItem) {
        guard let output = item.representedObject as? AudioOutput else { return }
        select(output)
    }

    private func selectRow(_ row: Int) {
        guard outputs.indices.contains(row) else { return }
        select(outputs[row])
    }

    private func select(_ output: AudioOutput) {
        guard !isFinishingSelection else { return }
        do {
            let changed = try AudioOutputs.select(output)
            let message = SndLanguage.outputConfirmation(for: output.name, changed: changed)
            isFinishingSelection = true
            window.orderOut(nil)
            Task {
                await postOutputNotification(message)
                NSApp.terminate(nil)
            }
        } catch {
            reloadOutputs(message: error.localizedDescription)
        }
    }

    private func postOutputNotification(_ message: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert]) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Snd"
            content.body = message
            // Let Notification Center deliver the confirmation after the picker quits.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            try await center.add(request)
        } catch {
            NSLog("Could not post Snd output confirmation: %@", error.localizedDescription)
        }
    }
}

@main
private enum Snd {
    @MainActor
    static func main() {
        if AlfredCommand.handle(CommandLine.arguments.dropFirst()) { return }

        let app = NSApplication.shared
        let picker = Picker()
        app.delegate = picker
        picker.installMenu(on: app)
        withExtendedLifetime(picker) {
            app.run()
        }
    }
}
