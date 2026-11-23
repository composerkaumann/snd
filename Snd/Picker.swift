import AppKit

@MainActor
private final class PickerWindow: NSWindow {
    var choose: ((Int) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers.isEmpty {
                if let key = event.charactersIgnoringModifiers, let number = Int(key),
                   (1...9).contains(number) {
                    if !event.isARepeat { choose?(number - 1) }
                    return
                }
                switch event.keyCode {
                case 36, 53, 76:
                    if !event.isARepeat { close() }
                    return
                default:
                    break
                }
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class Picker: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let window = PickerWindow(
        contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let footer = NSTextField(wrappingLabelWithString: "")
    private var outputs: [AudioOutput] = []
    private var current: UInt32?

    func installMenu(on app: NSApplication) {
        let menuBar = NSMenu()
        let appMenuItem = NSMenuItem()
        menuBar.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Snd")
        appMenuItem.submenu = appMenu
        let quit = NSMenuItem(title: "Quit Snd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = app
        appMenu.addItem(quit)

        let outputMenu = NSMenu(title: "Heliväljund")
        outputMenu.delegate = self
        let outputMenuItem = NSMenuItem(title: outputMenu.title, action: nil, keyEquivalent: "")
        menuBar.addItem(outputMenuItem)
        outputMenuItem.submenu = outputMenu
        app.mainMenu = menuBar
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
        show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window.isVisible { focusWindow() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func configureWindow() {
        window.title = "Heliväljund"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.choose = { [weak self] in self?.selectRow($0) }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("output"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = 32
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(selectClickedRow)
        table.setAccessibilityLabel("Saadaolevad heliväljundid")

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
            let hint = "\(keys) vali · Return või Esc sulge"
            footer.stringValue = message ?? (outputs.isEmpty ? "Saadaolevaid heliväljundeid pole." : hint)
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
            let status = NSTextField(labelWithString: "Kasutusel")
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

    @objc private func selectClickedRow() {
        selectRow(table.clickedRow)
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
        do {
            try AudioOutputs.select(output)
            window.close()
        } catch {
            reloadOutputs(message: error.localizedDescription)
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
