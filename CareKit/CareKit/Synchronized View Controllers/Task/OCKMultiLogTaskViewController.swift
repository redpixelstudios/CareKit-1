//
//  OCKMultiLogTaskViewController.swift
//
//  Created by Pablo Gallastegui on 6/12/19.
//  Copyright © 2019 Red Pixel Studios. All rights reserved.
//

import UIKit
import CareKitUI
import CareKitStore

/// An synchronized view controller that displays a single event and it's outcomes and allows the patient to log outcomes.
///
/// - Note: `OCKEventViewController`s are created by specifying a task and an event query. If the event query
/// returns more than one event, only the first event will be displayed.
open class OCKMultiLogTaskViewController<Store: OCKStoreProtocol>: OCKEventViewController<Store>, OCKMultiLogTaskViewDelegate {

    private var logOptions = [String]()
    
    public var taskView: OCKMultiLogTaskView {
        guard let view = view as? OCKMultiLogTaskView else { fatalError("Unexpected type") }
        return view
    }
    
    /// Initialize using an identifier.
    ///
    /// - Parameters:
    ///   - style: A style that determines which subclass will be instantiated.
    ///   - storeManager: A store manager that will be used to provide synchronization.
    ///   - taskIdentifier: The identifier event's task.
    ///   - eventQuery: An event query that specifies which events will be queried and displayed.
    public init(storeManager: OCKSynchronizedStoreManager<Store>, taskIdentifier: String, eventQuery: OCKEventQuery, logOptions:[String] = []) {
        super.init(storeManager: storeManager, taskIdentifier: taskIdentifier, eventQuery: eventQuery,
                   loadDefaultView: { OCKBindableMultiLogTaskView<Store.Task, Store.Outcome>() })
        
        self.logOptions = logOptions
        self.taskView.addOptions(logOptions)
    }
    
    /// Initialize using a task.
    ///
    /// - Parameters:
    ///   - storeManager: A store manager that will be used to provide synchronization.
    ///   - task: The task to which the event to be displayed belongs.
    ///   - eventQuery: An event query that specifies which events will be queried and displayed.
    public convenience init(storeManager: OCKSynchronizedStoreManager<Store>, task: Store.Task, eventQuery: OCKEventQuery, logOptions:[String] = []) {
        self.init(storeManager: storeManager, taskIdentifier: task.identifier, eventQuery: eventQuery, logOptions: logOptions)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        taskView.delegate = self
        taskView.multiLogDelegate = self
    }
    
    // MARK: OCKSimpleLogTaskViewDelegate
    
    /// This method will be called each time the taps on a logged record. Override this method in a subclass to change the behavior.
    ///
    /// - Parameters:
    ///   - simpleLogView: The view whose button was tapped.
    ///   - button: The button that was tapped.
    ///   - index: The index of the button that was tapped.
    open func logTaskView(_ logTaskView: OCKLogTaskView, didSelectItem button: OCKButton, at index: Int) {
        let logInfo = [button.titleLabel?.text, button.detailLabel?.text]
            .compactMap { $0 }
            .joined(separator: " - ")

        let actionSheet = UIAlertController(title: "Log Entry", message: logInfo, preferredStyle: .actionSheet)
        let cancel = UIAlertAction(title: OCKStyle.strings.cancel, style: .default, handler: nil)
        
        let delete = UIAlertAction(title: OCKStyle.strings.delete, style: .destructive) { [weak self] (action) in
            guard let self = self else { return }
            
            // Sort values by date value
            let values = self.event?.convert().outcome?.values ?? []
            let sortedValues = values.sorted {
                guard let date1 = $0.createdAt, let date2 = $1.createdAt else { return true }
                return date1 < date2
            }
            
            guard index < sortedValues.count else { return }
            let intValue = sortedValues[index].integerValue
            self.deleteOutcomeValue(intValue)
        }

        [delete, cancel].forEach { actionSheet.addAction($0) }
        present(actionSheet, animated: true, completion: nil)
    }
    
    /// This method will be called each time the taps on a log button. Override this method in a subclass to change the behavior.
    ///
    /// - Parameters:
    ///   - multiLogTaskView: The view containing the log item.
    ///   - logButton: The item in the log that was selected.
    ///   - index: The index of the item in the log.
    open func multiLogTaskView(_ multiLogTaskView: OCKMultiLogTaskView, didSelectLog logButton: OCKButton, at index: Int) {
        let newOutcomeValue = OCKOutcomeValue(logOptions[index])
        
        if let outcome = event?.outcome {
            
            // save a new outcome value if there is already an outcome
            var convertedOutcome = outcome.convert()
            var newValues = convertedOutcome.values
            newValues.append(newOutcomeValue)
            
            convertedOutcome.values = newValues
            let updatedOutcome = Store.Outcome(value: convertedOutcome)
            
            storeManager.store.updateOutcomes([updatedOutcome], queue: .main) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success: break
                case .failure(let error):
                    self.delegate?.eventViewController(self, didFailWithError: error)
                }
            }
        } else {
            self.saveNewOutcome(withValues: [newOutcomeValue])
        }
    }
}
