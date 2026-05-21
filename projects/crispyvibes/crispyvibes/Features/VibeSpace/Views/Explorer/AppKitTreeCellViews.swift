import AppKit

final class AppKitTreeCellView: NSTableCellView, NSTextFieldDelegate {
    let chevronButton = NSButton()
    let iconView = NSImageView()
    let labelField = NSTextField(string: "")
    var currentAction: ((FileTreeAction) -> Void)?
    var currentNode: TreeNode?
    var disclosureToggleAction: (() -> Void)?
    var renameTextSetter: ((String) -> Void)?
    var isInRenameMode = false
    var hasQueuedRenameFocus = false
    var didDispatchRenameEndAction = false
    private var chevronWidthConstraint: NSLayoutConstraint?
    private var chevronHeightConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var chevronLeadingConstraint: NSLayoutConstraint?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var labelLeadingConstraint: NSLayoutConstraint?
    private var labelTrailingConstraint: NSLayoutConstraint?

    var isRenameInteractionActive: Bool {
        isInRenameMode || hasQueuedRenameFocus
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        setAccessibilityElement(true)
        setAccessibilityIdentifier("explorer.row")
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.isBordered = false
        chevronButton.setButtonType(.momentaryChange)
        chevronButton.imagePosition = .imageOnly
        chevronButton.imageScaling = .scaleProportionallyDown
        chevronButton.focusRingType = .none
        chevronButton.target = self
        chevronButton.action = #selector(toggleDisclosure)
        addSubview(chevronButton)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.lineBreakMode = .byTruncatingTail
        labelField.maximumNumberOfLines = 1
        applyScale()
        labelField.isEditable = false
        labelField.isSelectable = false
        labelField.isBordered = false
        labelField.drawsBackground = false
        labelField.focusRingType = .none
        applyLabelAccessibilityIdentifier()
        addSubview(labelField)

        chevronLeadingConstraint = chevronButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        chevronWidthConstraint = chevronButton.widthAnchor.constraint(equalToConstant: 14)
        chevronHeightConstraint = chevronButton.heightAnchor.constraint(equalToConstant: 14)
        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 4)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        labelLeadingConstraint = labelField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        labelTrailingConstraint = labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            chevronLeadingConstraint!,
            chevronButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidthConstraint!,
            chevronHeightConstraint!,

            iconLeadingConstraint!,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,

            labelLeadingConstraint!,
            labelTrailingConstraint!,
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyScale()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else { return nil }

        if hitView === chevronButton || hitView.isDescendant(of: chevronButton) {
            return hitView
        }

        if isInRenameMode,
           (hitView === labelField || hitView.isDescendant(of: labelField)) {
            return hitView
        }

        // Let the outline view own row clicks for the icon, label, and padding gap.
        // This keeps the whole row behaving like one click target.
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentAction = nil
        disclosureToggleAction = nil
        renameTextSetter = nil
        currentNode = nil
    }

    func configure(
        node: TreeNode,
        isSelected: Bool,
        isRenaming: Bool,
        isExpanded: Bool,
        searchQuery: String,
        scale: CrispyVibesUIScale,
        onAction: @escaping (FileTreeAction) -> Void,
        onDisclosureToggle: @escaping () -> Void,
        renameTextSetter: @escaping (String) -> Void
    ) {
        currentNode = node
        currentAction = onAction
        disclosureToggleAction = onDisclosureToggle
        self.renameTextSetter = renameTextSetter
        update(
            node: node,
            isSelected: isSelected,
            isRenaming: isRenaming,
            isExpanded: isExpanded,
            searchQuery: searchQuery,
            scale: scale
        )
    }

    func update(
        node: TreeNode,
        isSelected: Bool,
        isRenaming: Bool,
        isExpanded: Bool,
        searchQuery: String,
        scale: CrispyVibesUIScale
    ) {
        let item = node.item
        applyScale(scale)
        let ignoredAlpha: CGFloat = item.isGitIgnored && !isSelected ? 0.48 : 1.0

        if item.isDirectory {
            let chevronName = isExpanded ? "chevron.down" : "chevron.right"
            chevronButton.image = NSImage(systemSymbolName: chevronName, accessibilityDescription: nil)
            chevronButton.contentTintColor = .secondaryLabelColor
            chevronButton.isHidden = false
            chevronButton.isEnabled = !isInRenameMode
        } else {
            chevronButton.isHidden = true
            chevronButton.isEnabled = false
        }

        let iconName: String
        if item.isDirectory {
            iconName = "folder"
        } else if item.isMarkdown {
            iconName = "doc.richtext.fill"
        } else {
            iconName = "doc.fill"
        }
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iconView.contentTintColor = item.isDirectory ? .controlAccentColor : .secondaryLabelColor
        iconView.alphaValue = ignoredAlpha

        if !isInRenameMode {
            labelField.stringValue = item.displayName
        }
        labelField.alphaValue = ignoredAlpha
        setAccessibilityLabel(item.displayName)
        setAccessibilityValue(item.displayName)

        if isRenaming && !isInRenameMode {
            beginRenameMode(for: item)
        } else if !isRenaming && isInRenameMode {
            cancelRenameMode()
        }

        if isSelected {
            wantsLayer = true
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            let borderShape = CrispyVibesBorderShape(rawValue: UserDefaults.standard.string(forKey: CrispyVibesThemeManager.borderShapeKey) ?? "")
                ?? CrispyVibesTheme.default.borderShape
            layer?.cornerRadius = borderShape == .square ? 0 : 4
        } else {
            layer?.backgroundColor = nil
        }
    }

    @objc func toggleDisclosure() {
        guard currentNode?.item.isDirectory == true, !isInRenameMode else { return }
        disclosureToggleAction?()
    }

    private func applyScale(_ scale: CrispyVibesUIScale = .current()) {
        labelField.font = NSFont.systemFont(ofSize: scale.textSize(13))
        chevronLeadingConstraint?.constant = scale.spacing(4)
        chevronWidthConstraint?.constant = scale.iconSize(16)
        chevronHeightConstraint?.constant = scale.iconSize(16)
        iconLeadingConstraint?.constant = scale.spacing(4)
        iconWidthConstraint?.constant = scale.iconSize(18)
        iconHeightConstraint?.constant = scale.iconSize(18)
        labelLeadingConstraint?.constant = scale.spacing(4)
        labelTrailingConstraint?.constant = -scale.spacing(4)
    }
}

final class AppKitTreeLoadingCellView: NSTableCellView {
    private let progressIndicator = NSProgressIndicator()
    private let labelField = NSTextField(labelWithString: "Loading…")
    private var progressLeadingConstraint: NSLayoutConstraint?
    private var labelLeadingConstraint: NSLayoutConstraint?
    private var labelTrailingConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        addSubview(progressIndicator)

        labelField.translatesAutoresizingMaskIntoConstraints = false
        applyScale()
        labelField.textColor = .secondaryLabelColor
        addSubview(labelField)

        progressLeadingConstraint = progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18)
        labelLeadingConstraint = labelField.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 6)
        labelTrailingConstraint = labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        NSLayoutConstraint.activate([
            progressLeadingConstraint!,
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelLeadingConstraint!,
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelTrailingConstraint!
        ])
        applyScale()
    }

    func configure(scale: CrispyVibesUIScale) {
        applyScale(scale)
        progressIndicator.startAnimation(nil)
    }

    private func applyScale(_ scale: CrispyVibesUIScale = .current()) {
        labelField.font = NSFont.systemFont(ofSize: scale.textSize(13))
        progressLeadingConstraint?.constant = scale.spacing(18)
        labelLeadingConstraint?.constant = scale.spacing(6)
        labelTrailingConstraint?.constant = -scale.spacing(4)
    }
}
