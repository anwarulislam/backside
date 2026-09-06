import AppKit

@MainActor
final class NoteLibraryWindowController: NSWindowController {
    private let libraryViewController: NoteLibraryViewController

    init(store: NoteStore) {
        libraryViewController = NoteLibraryViewController(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_050, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Backside Library"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 760, height: 480)
        window.center()
        window.contentViewController = libraryViewController
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        libraryViewController.reloadData()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class NoteLibraryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    private let store: NoteStore
    private let appTable = NSTableView()
    private let noteTable = NSTableView()
    private let searchField = NSSearchField()
    private let editor = NSTextView()
    private let detailTitle = NSTextField(labelWithString: "Select a note")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton(title: "", target: nil, action: nil)
    private var applications: [AppNotes] = []
    private var notes: [StoredNote] = []
    private var selectedAppID: String?
    private var selectedNote: StoredNote?
    private var isLoadingEditor = false

    init(store: NoteStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let sidebar = makeSidebar()
        let content = makeContent()
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)
        split.setPosition(220, ofDividerAt: 0)
        view = split
    }

    func reloadData() {
        let previousApp = selectedAppID
        let previousNote = selectedNote?.id
        applications = store.applications(search: searchField.stringValue)
        if let previousApp, !applications.contains(where: { $0.id == previousApp }) { selectedAppID = nil }
        appTable.reloadData()
        selectAppRow()
        reloadNotes(selecting: previousNote)
    }

    private func makeSidebar() -> NSView {
        let container = NSView()
        let label = NSTextField(labelWithString: "NOTES BY APP")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        configure(table: appTable, identifier: NSUserInterfaceItemIdentifier("apps"))
        appTable.rowHeight = 34
        let scroll = NSScrollView()
        scroll.documentView = appTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), label.topAnchor.constraint(equalTo: container.topAnchor, constant: 17),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeContent() -> NSView {
        let container = NSView()
        searchField.placeholderString = "Search notes"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let innerSplit = NSSplitView()
        innerSplit.isVertical = true
        innerSplit.dividerStyle = .thin
        innerSplit.translatesAutoresizingMaskIntoConstraints = false
        let noteList = makeNoteList()
        let detail = makeDetail()
        innerSplit.addArrangedSubview(noteList)
        innerSplit.addArrangedSubview(detail)
        innerSplit.setPosition(295, ofDividerAt: 0)
        container.addSubview(searchField)
        container.addSubview(innerSplit)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            innerSplit.leadingAnchor.constraint(equalTo: container.leadingAnchor), innerSplit.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            innerSplit.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12), innerSplit.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeNoteList() -> NSView {
        configure(table: noteTable, identifier: NSUserInterfaceItemIdentifier("notes"))
        noteTable.rowHeight = 58
        let scroll = NSScrollView()
        scroll.documentView = noteTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    private func makeDetail() -> NSView {
        let container = NSView()
        detailTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        detailTitle.lineBreakMode = .byTruncatingTail
        detailTitle.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        pinButton.bezelStyle = .texturedRounded
        pinButton.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin note")
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 13, height: 10)
        editor.delegate = self
        scroll.documentView = editor
        container.addSubview(detailTitle)
        container.addSubview(metadataLabel)
        container.addSubview(pinButton)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            detailTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18), detailTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 16), detailTitle.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -8),
            metadataLabel.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor), metadataLabel.topAnchor.constraint(equalTo: detailTitle.bottomAnchor, constant: 3),
            pinButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), pinButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: metadataLabel.bottomAnchor, constant: 11), scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }

    private func configure(table: NSTableView, identifier: NSUserInterfaceItemIdentifier) {
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = false
        let column = NSTableColumn(identifier: identifier)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    private func selectAppRow() {
        let row = selectedAppID.flatMap { id in applications.firstIndex(where: { $0.id == id }).map { $0 + 1 } } ?? 0
        appTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func reloadNotes(selecting id: String? = nil) {
        notes = store.notes(appID: selectedAppID, search: searchField.stringValue)
        noteTable.reloadData()
        let row = id.flatMap { requested in notes.firstIndex(where: { $0.id == requested }) } ?? (notes.isEmpty ? nil : 0)
        if let row { noteTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); show(note: notes[row]) }
        else { show(note: nil) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == appTable ? applications.count + 1 : notes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let primary = NSTextField(labelWithString: "")
        primary.font = .systemFont(ofSize: 13, weight: .medium)
        primary.lineBreakMode = .byTruncatingTail
        primary.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(primary)
        if tableView == appTable {
            let item = row == 0 ? AppNotes(id: "", name: "All Notes", count: applications.reduce(0) { $0 + $1.count }) : applications[row - 1]
            primary.stringValue = "\(item.name)  ·  \(item.count)"
            NSLayoutConstraint.activate([primary.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14), primary.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), primary.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        } else {
            let note = notes[row]
            primary.stringValue = (note.isPinned ? "⌖  " : "") + note.windowTitle
            let preview = NSTextField(labelWithString: note.markdown.replacingOccurrences(of: "\n", with: " "))
            preview.font = .systemFont(ofSize: 11)
            preview.textColor = .secondaryLabelColor
            preview.lineBreakMode = .byTruncatingTail
            preview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(preview)
            NSLayoutConstraint.activate([
                primary.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), primary.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), primary.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
                preview.leadingAnchor.constraint(equalTo: primary.leadingAnchor), preview.trailingAnchor.constraint(equalTo: primary.trailingAnchor), preview.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 3)
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table == appTable {
            selectedAppID = table.selectedRow > 0 ? applications[table.selectedRow - 1].id : nil
            reloadNotes(selecting: nil)
        } else if table == noteTable, notes.indices.contains(table.selectedRow) {
            show(note: notes[table.selectedRow])
        }
    }

    func controlTextDidChange(_ obj: Notification) { reloadData() }

    func textDidChange(_ notification: Notification) {
        guard !isLoadingEditor, let selectedNote else { return }
        store.update(markdown: editor.string, id: selectedNote.id)
    }

    @objc private func togglePin() {
        guard let selectedNote else { return }
        store.setPinned(!selectedNote.isPinned, id: selectedNote.id)
        reloadNotes(selecting: selectedNote.id)
    }

    private func show(note: StoredNote?) {
        selectedNote = note
        isLoadingEditor = true
        editor.string = note?.markdown ?? ""
        editor.isEditable = note != nil
        isLoadingEditor = false
        detailTitle.stringValue = note?.windowTitle ?? "Select a note"
        metadataLabel.stringValue = note.map { "\($0.appName)  ·  updated \(Self.dateFormatter.localizedString(for: $0.updatedAt, relativeTo: Date()))" } ?? "Notes are saved locally on this Mac"
        pinButton.isHidden = note == nil
        pinButton.image = NSImage(systemSymbolName: note?.isPinned == true ? "pin.fill" : "pin", accessibilityDescription: "Pin note")
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
