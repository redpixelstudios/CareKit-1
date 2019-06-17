//
//  OCKMultiLogTaskView.swift
//
//  Created by Pablo Gallastegui on 6/12/19.
//  Copyright © 2019 Red Pixel Studios. All rights reserved.
//


import UIKit

/// Protocol for interactions with an `OCKSimpleLogTaskView`.
public protocol OCKCustomLogTaskViewDelegate: OCKLogTaskViewDelegate {
    
    /// Called when a log button was selected.
    ///
    /// - Parameters:
    ///   - multiLogTaskView: The view containing the log item.
    ///   - logButton: The item in the log that was selected.
    ///   - index: The index of the item in the log.
    func customLogTaskView(_ customLogTaskView: OCKCustomLogTaskView, didSelectValue value: Any, withUnits units: String?)
}

/// A card that displays a header, multi-line label, multiple log buttons, and a dynamic vertical stack of logged items.
/// In CareKit, this view is intended to display a particular event for a task. When one of the log buttons is pressed,
/// a new outcome is created for the event.
///
/// To insert custom views vertically the view, see `contentStack`. To modify the logged items, see
/// `updateItem`, `appendItem`, `insertItem`, `removeItem` and `clearItems`.
///
///     +--------------------------------------------------------------+
///     |                                                              |
///     | [title]                                       [detail        |
///     | [detail]                                      disclosure]    |
///     |                                                              |
///     |                                                              |
///     |  ----------------------------------------------------------  |
///     |                                                              |
///     |   [instructions]                                             |
///     |                                                              |
///     |  +--------------------------------------------------------+  |
///     |  | Content View (to be defined by user)                   |  |
///     |  +--------------------------------------------------------+  |
///     |                                                              |
///     +--------------------------------------------------------------+
///
open class OCKCustomLogTaskView: OCKLogTaskView {
    
    // MARK: Properties
    
    /// The button that can be hooked up to modify the list of logged items.
    public let logButton: OCKButton = {
        let button = OCKLabeledButton()
        button.animatesStateChanges = false
        button.setTitle(OCKStyle.strings.log, for: .normal)
        button.handlesSelectionStateAutomatically = false        
        return button
    }()
    
    /// Delegate that gets notified of interactions with the `OCKSimpleLogTaskView`.
    public weak var customLogDelegate: OCKCustomLogTaskViewDelegate?
    
    /// The horizontal stack view that holds the log buttons.
    public let contentView: OCKStackView = {
        var stackView = OCKStackView(style: .plain)
        stackView.showsOuterSeparators = false
        stackView.axis = .vertical
        return stackView
    }()
    
    override internal func setup() {
        self.logButtonPlaceholder = self.logButton
        
        super.setup()
    }
    
    override internal func styleSubviews() {
        super.styleSubviews()
        
        contentView.spacing = directionalLayoutMargins.top + directionalLayoutMargins.bottom
    }
    
    override internal func addSubviews() {
        super.addSubviews()        
        [headerView, instructionsLabel, contentView, logButton, logItemsStackView].forEach { contentStackView.addArrangedSubview($0) }
    }
}
