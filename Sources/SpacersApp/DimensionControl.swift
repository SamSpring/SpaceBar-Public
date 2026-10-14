import AppKit
import SpacersCore

@MainActor
final class TrackingSlider: NSSlider {
    private(set) var isTracking = false
    var onTrackingEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        super.mouseDown(with: event)
        isTracking = false
        onTrackingEnded?()
    }
}

@MainActor
final class DimensionControl: NSStackView {
    let slider = TrackingSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private let dimension: ItemDimension
    private let id: UUID
    private weak var coordinator: AppDelegate?

    init(item: ItemConfiguration, dimension: ItemDimension, owner: AppDelegate, fixedSliderWidth: CGFloat? = nil) {
        self.id = item.id
        self.dimension = dimension
        self.coordinator = owner
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        distribution = .fill
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.minValue = dimension.range.lowerBound
        slider.maxValue = dimension.range.upperBound
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.toolTip = dimension == .width ? "Spacer width" : "Divider height; tall values are capped to fit the menu bar"
        slider.setAccessibilityLabel("\(item.kind.title) \(dimension.title.lowercased())")
        slider.onTrackingEnded = { [weak self] in self?.finish() }
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        addArrangedSubview(slider)
        addArrangedSubview(valueLabel)
        if let fixedSliderWidth {
            slider.widthAnchor.constraint(equalToConstant: fixedSliderWidth).isActive = true
        } else {
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        }
        valueLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        refresh(item)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    func refresh(_ item: ItemConfiguration) {
        guard !slider.isTracking else { return }
        slider.isEnabled = coordinator?.layoutManager.isBusy != true
        slider.doubleValue = item[dimension]
        valueLabel.stringValue = dimension.label(for: item[dimension])
    }

    private var roundedValue: Double {
        let value = dimension == .opacity ? (slider.doubleValue * 100).rounded() / 100 : slider.doubleValue.rounded()
        return min(dimension.range.upperBound, max(dimension.range.lowerBound, value))
    }

    @objc private func changed() {
        let value = roundedValue
        valueLabel.stringValue = dimension.label(for: value)
        if slider.isTracking {
            coordinator?.preview(dimension, value: value, for: id)
        } else {
            // Keyboard and accessibility actions commit immediately.
            coordinator?.set(dimension, value: value, for: id)
        }
    }

    private func finish() {
        guard let owner = coordinator else { return }
        owner.set(dimension, value: roundedValue, for: id)
        if let item = owner.configuration.items.first(where: { $0.id == id }) { refresh(item) }
    }
}

@MainActor
final class MasterDividerControl: NSStackView {
    let slider = TrackingSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private let dimension: ItemDimension
    private weak var coordinator: AppDelegate?

    init(dimension: ItemDimension, owner: AppDelegate, fixedSliderWidth: CGFloat? = nil) {
        precondition(dimension == .height || dimension == .opacity)
        self.dimension = dimension
        coordinator = owner
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        distribution = .fill
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.minValue = dimension.range.lowerBound
        slider.maxValue = dimension.range.upperBound
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.toolTip = dimension == .height ? "Set all divider heights; tall values are capped to fit the menu bar" : "Set the opacity of all dividers together"
        slider.setAccessibilityLabel("All dividers \(dimension.title.lowercased())")
        slider.onTrackingEnded = { [weak self] in self?.finish() }
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.toolTip = "Mixed means saved divider values differ. Moving this slider sets all dividers to the same \(dimension.title.lowercased())."
        addArrangedSubview(slider)
        addArrangedSubview(valueLabel)
        if let fixedSliderWidth {
            slider.widthAnchor.constraint(equalToConstant: fixedSliderWidth).isActive = true
        } else {
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        }
        valueLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    func refresh() {
        guard !slider.isTracking, let owner = coordinator else { return }
        let dividers = owner.configuration.items.filter { $0.kind == .divider }
        slider.isEnabled = !dividers.isEmpty && owner.startupError == nil && !owner.layoutManager.isBusy
        if let value = owner.commonDividerValue(dimension) {
            slider.doubleValue = value
            valueLabel.stringValue = dimension.label(for: value)
        } else if dividers.isEmpty {
            slider.doubleValue = dimension == .height ? 16 : 0.45
            valueLabel.stringValue = "—"
        } else {
            slider.doubleValue = dividers.map { $0[dimension] }.reduce(0, +) / Double(dividers.count)
            valueLabel.stringValue = "Mixed"
        }
    }

    private var roundedValue: Double {
        let value = dimension == .opacity ? (slider.doubleValue * 100).rounded() / 100 : slider.doubleValue.rounded()
        return min(dimension.range.upperBound, max(dimension.range.lowerBound, value))
    }

    @objc private func changed() {
        valueLabel.stringValue = dimension.label(for: roundedValue)
        if slider.isTracking {
            coordinator?.previewDividers(dimension, value: roundedValue)
        } else {
            _ = coordinator?.setDividers(dimension, value: roundedValue)
            refresh()
        }
    }

    private func finish() {
        _ = coordinator?.setDividers(dimension, value: roundedValue)
        refresh()
    }
}

@MainActor
final class MenuMasterDividerView: NSView {
    init(dimension: ItemDimension, owner: AppDelegate) {
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 58))
        let label = NSTextField(labelWithString: "All Divider \(dimension.title)")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let control = MasterDividerControl(dimension: dimension, owner: owner, fixedSliderWidth: 166)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }
}

@MainActor
final class MenuDimensionView: NSView {
    init(item: ItemConfiguration, dimension: ItemDimension, owner: AppDelegate) {
        super.init(frame: NSRect(x: 0, y: 0, width: 306, height: 58))
        let label = NSTextField(labelWithString: dimension.title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let control = DimensionControl(item: item, dimension: dimension, owner: owner, fixedSliderWidth: 166)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }
}
