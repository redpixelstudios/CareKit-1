//
//  OCKCustomLogTaskViewController.swift
//
//  Created by Pablo Gallastegui on 6/12/19.
//  Copyright © 2019 Red Pixel Studios. All rights reserved.
//


import UIKit

/// Protocol for interactions with an `OCKCustomLogTaskViewController`.
public protocol OCKCustomLogTaskViewControllerDataSource: class {
    
    /// Called when a log button was selected.
    ///
    /// - Parameters:
    ///   - multiLogTaskView: The view containing the log item.
    ///   - logButton: The item in the log that was selected.
    ///   - index: The index of the item in the log.
    func customLogTaskViewController<T>(valuesForCustomLogTaskViewController customLogTaskViewController: OCKCustomLogTaskViewController<T>) -> [OCKOutcomeValue]
}

/// An synchronized view controller that displays a single event and it's outcomes and allows the patient to log outcomes.
///
/// - Note: `OCKEventViewController`s are created by specifying a task and an event query. If the event query
/// returns more than one event, only the first event will be displayed.
open class OCKCustomLogTaskViewController<Store: OCKStoreProtocol>: OCKLogTaskViewController<Store, OCKCustomLogTaskView> {
    
    // MARK: Properties
    
    /// Delegate that gets notified of interactions with the `OCKSimpleLogTaskView`.
    public weak var dataSource: OCKCustomLogTaskViewControllerDataSource?
    
    /// Initialize using an identifier.
    ///
    /// - Parameters:
    ///   - style: A style that determines which subclass will be instantiated.
    ///   - storeManager: A store manager that will be used to provide synchronization.
    ///   - taskIdentifier: The identifier event's task.
    ///   - eventQuery: An event query that specifies which events will be queried and displayed.
    public init(storeManager: OCKSynchronizedStoreManager<Store>, taskIdentifier: String, eventQuery: OCKEventQuery) {
        super.init(storeManager: storeManager, taskIdentifier: taskIdentifier, eventQuery: eventQuery,
                   loadDefaultView: { OCKBindableCustomLogTaskView<Store.Task, Store.Outcome>() })
    }
    
    /// Initialize using a task.
    ///
    /// - Parameters:
    ///   - storeManager: A store manager that will be used to provide synchronization.
    ///   - task: The task to which the event to be displayed belongs.
    ///   - eventQuery: An event query that specifies which events will be queried and displayed.
    public convenience init(storeManager: OCKSynchronizedStoreManager<Store>, task: Store.Task, eventQuery: OCKEventQuery) {
        self.init(storeManager: storeManager, taskIdentifier: task.identifier, eventQuery: eventQuery)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        taskView.logButton.addTarget(self, action: #selector(logButtonPressed(_:)), for: .touchUpInside)
    }
    
    @objc private func logButtonPressed(_ sender: OCKButton) {
        guard let outcomeValues = self.dataSource?.customLogTaskViewController(valuesForCustomLogTaskViewController: self) else { return }
        
        if let outcome = event?.outcome {            
            // save a new outcome value if there is already an outcome
            var convertedOutcome = outcome.convert()
            var newValues = convertedOutcome.values
            
            for outcomeValue in outcomeValues {
                newValues.append(outcomeValue)
            }
            
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
            self.saveNewOutcome(withValues: outcomeValues)
        }
    }
    
}
