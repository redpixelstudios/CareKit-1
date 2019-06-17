/*
 Copyright (c) 2019, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3. Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

public extension OCKStoreProtocol {
    
    // MARK: Outcomes
    
    func fetchOutcome(taskVersionID: OCKLocalVersionID, occurenceIndex: Int, queue: DispatchQueue = .main,
                      completion: @escaping OCKResultClosure<Outcome>) {
        fetchEvent(withTaskVersionID: taskVersionID, occurenceIndex: occurenceIndex, queue: queue, completion: { result in
            switch result {
            case .failure(let error): completion(.failure(.fetchFailed(reason: "Failed to fetch outcome. \(error.localizedDescription)")))
            case .success(let event):
                guard let outcome = event.outcome else { completion(.failure(.fetchFailed(reason: "No matching outcome found"))); return }
                completion(.success(outcome))
            }
        })
    }
    
    // MARK: Events
    
    func fetchEvents(taskIdentifier: String, query: OCKEventQuery, queue: DispatchQueue = .main,
                     completion: @escaping OCKResultClosure<[OCKEvent<Task, Outcome>]>) {
        fetchTask(withIdentifier: taskIdentifier, queue: queue) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let task):
                guard let task = task else { completion(.failure(.fetchFailed(reason: "No task with identifier: \(taskIdentifier)"))); return }
                self.fetchEvents(task: task, query: query, previousEvents: [], queue: queue) { result in
                    completion(result)
                }
            }
        }
    }
    
    func fetchEvent(withTaskVersionID taskVersionID: OCKLocalVersionID, occurenceIndex: Int,
                    queue: DispatchQueue = .main, completion: @escaping OCKResultClosure<OCKEvent<Task, Outcome>>) {
        
        fetchTask(withVersionID: taskVersionID, queue: queue, completion: { result in
            switch result {
            case .failure(let error): completion(.failure(.fetchFailed(reason: "Failed to fetch task. \(error.localizedDescription)")))
            case .success(let task):
                guard let task = task, let scheduleEvent = task.convert().schedule.event(forOccurenceIndex: occurenceIndex) else {
                    completion(.failure(.fetchFailed(reason: "Invalid occurence \(occurenceIndex) for task with version ID: \(taskVersionID)")))
                    return
                }
                let early = scheduleEvent.start.addingTimeInterval(-1)
                let late = scheduleEvent.end.addingTimeInterval(1)
                let query = OCKOutcomeQuery(start: early, end: late)
                self.fetchOutcome(.taskVersion(taskVersionID), query: query, queue: queue, completion: { result in
                    switch result {
                    case .failure(let error): completion(.failure(.fetchFailed(reason: "Couldn't find outcome. \(error.localizedDescription)")))
                    case .success(let outcome):
                        let event = OCKEvent(task: task, outcome: outcome, scheduleEvent: scheduleEvent)
                        completion(.success(event))
                    }
                })
            }
        })
    }
    
    // This is a recursive async function that gets all events within a query for a given task, examining all past versions of the task
    private func fetchEvents(task: Task, query: OCKEventQuery, previousEvents: [OCKEvent<Task, Outcome>],
                             queue: DispatchQueue = .main, completion: @escaping (Result<[OCKEvent<Task, Outcome>], OCKStoreError>) -> Void) {
        let converted = task.convert()
        guard let versionID = converted.localDatabaseID else { completion(.failure(.fetchFailed(reason: "Task didn't have a versionID"))); return }
        let start = max(converted.schedule.start, query.start)
        let end = converted.schedule.end == nil ? query.end : min(converted.schedule.end!, query.end)
        let outcomeQuery = OCKOutcomeQuery(start: start, end: end)
        let scheduleEvents = converted.schedule.events(from: start, to: end)
        self.fetchOutcomes(.taskVersion(versionID), query: outcomeQuery, queue: queue, completion: { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let outcomes):
                let events = self.join(task: task, with: outcomes, and: scheduleEvents) + previousEvents
                guard let version = task.convert().previousVersionID else { completion(.success(events)); return }
                self.fetchTask(withVersionID: version, queue: queue, completion: { result in
                    switch result {
                    case .failure(let error): completion(.failure(error))
                    case .success(let task):
                        guard let task = task else {
                            completion(.failure(.fetchFailed(reason: "No task with identifer \(version)")))
                            return
                        }
                        let nextEndDate = converted.schedule.start
                        let nextStartDate = max(query.start, task.convert().schedule.start)
                        let nextQuery = OCKEventQuery(start: nextStartDate, end: nextEndDate)
                        self.fetchEvents(task: task, query: nextQuery, previousEvents: events, queue: queue, completion: { result in
                            completion(result)
                        })
                    }
                })
            }
        })
    }
    
    private func join(task: Task, with outcomes: [Outcome], and scheduleEvents: [OCKScheduleEvent]) -> [OCKEvent<Task, Outcome>] {
        guard !scheduleEvents.isEmpty else { return [] }
        let offset = scheduleEvents[0].occurence
        var events = scheduleEvents.map { OCKEvent<Task, Outcome>(task: task, outcome: nil, scheduleEvent: $0) }
        for outcome in outcomes {
            events[outcome.convert().taskOccurenceIndex - offset].outcome = outcome
        }
        return events
    }
    
    // MARK: Adherence
    
    func fetchAdherence(forTasks identifiers: [String]? = nil, query: OCKAdherenceQuery,
                        queue: DispatchQueue = .main, completion: @escaping OCKResultClosure<[OCKAdherence]>) {
        
        let anchor = identifiers == nil ? nil : OCKTaskAnchor.taskIdentifiers(identifiers!)
        let taskQuery = OCKTaskQuery(from: query)
        
        fetchTasks(anchor, query: taskQuery, queue: queue) { result in
            switch result {
            case .failure(let error): completion(.failure(.fetchFailed(reason: "Failed to fetch adherence. \(error.localizedDescription)")))
            case .success(let tasks):
                let tasks = tasks.filter { $0.convert().impactsAdherence }
                guard !tasks.isEmpty else {
                    let adherences = taskQuery.dates().map { _ in OCKAdherence.noTasks }
                    completion(.success(adherences))
                    return
                }
                let group = DispatchGroup()
                var error: Error?
                var events: [OCKEvent<Task, Outcome>] = []
                for identifier in tasks.map({ $0.convert().identifier }) {
                    group.enter()
                    let query = OCKEventQuery(from: query)
                    self.fetchEvents(taskIdentifier: identifier, query: query, queue: queue, completion: { result in
                        switch result {
                        case .failure(let fetchError):      error = fetchError
                        case .success(let fetchedEvents):   events.append(contentsOf: fetchedEvents)
                        }
                        group.leave()
                    })
                }
                group.notify(queue: .global(qos: .userInitiated), execute: {
                    if let error = error {
                        completion(.failure(.fetchFailed(reason: "Failed to fetch completion for tasks! \(error.localizedDescription)")))
                        return
                    }
                    let groupedEvents = self.groupEventsByDate(events: events, after: query.start, before: query.end)
                    let completionPercentages = groupedEvents.enumerated().map { (index, events) -> OCKAdherence in
                        let date = Calendar.current.date(byAdding: .day, value: index, to: query.start)!
                        return self.computeAverageCompletion(for: events, on: date)
                    }
                    queue.async { completion(.success(completionPercentages)) }
                })
            }
        }
    }
    
    private func groupEventsByDate(events: [OCKEvent<Task, Outcome>], after start: Date, before end: Date) -> [[OCKEvent<Task, Outcome>]] {
        var days: [[OCKEvent<Task, Outcome>]] = []
        let grabDayIndex = { (date: Date) in Calendar.current.dateComponents(Set([.day]), from: start, to: date).day! }
        let numberOfDays = grabDayIndex(end) + 1
        for _ in 0..<numberOfDays {
            days.append([])
        }
        for event in events {
            let dayIndex = grabDayIndex(event.scheduleEvent.start)
            days[dayIndex].append(event)
        }
        return days
    }
    
    private func computeAverageCompletion(for events: [OCKEvent<Task, Outcome>], on date: Date) -> OCKAdherence {
        guard !events.isEmpty else {
            return .noEvents
        }
        let events = events.map { $0.convert() }
        let percentsComplete = events.map(computeCompletion)
        let average = percentsComplete.reduce(0, +) / Double(events.count)
        return .progress(average)
    }
    
    private func computeCompletion(for event: OCKEvent<OCKTask, OCKOutcome>) -> Double {
        let expectedValues = event.scheduleEvent.element.targetValues
        
        var valuesRequiredForComplete = 0
        var unitValuesRequiredForComplete = [String: Double]()
        
        for expectedValue in expectedValues {
            if let units = expectedValue.units {
                let value = expectedValue.doubleValue ?? Double(expectedValue.integerValue ?? 0)
                unitValuesRequiredForComplete[units, default: 0] += value
            } else {
                valuesRequiredForComplete += 1
            }
        }
        
        var valueCount = 0
        var unitValues = [String: Double]()
        
        for storedValue in event.outcome?.values ?? [] {
            if let units = storedValue.units {
                let value = storedValue.doubleValue ?? Double(storedValue.integerValue ?? 0)
                unitValues[units, default: 0] += value
            } else {
                valueCount += 1
            }
        }
        
        let denominator = Double(valuesRequiredForComplete + unitValuesRequiredForComplete.keys.count)
        var numerator = Double(min(valueCount, valuesRequiredForComplete))
        
        unitValuesRequiredForComplete.forEach { (item) in
            let (units, value) = item
            numerator += min(1.0, unitValues[units, default: 0] / value)
        }
        
        let fractionComplete = numerator / denominator
        return fractionComplete
    }
    
    // MARK: Insights
    
    func fetchInsights(forTask identifier: String, query: OCKInsightQuery, queue: DispatchQueue = .main,
                       dailyAggregator: @escaping (_ outcomes: [OCKEvent<Task, Outcome>]) -> Double,
                       completion: @escaping OCKResultClosure<[Double]>) {
        let eventQuery = OCKEventQuery(from: query)
        fetchEvents(taskIdentifier: identifier, query: eventQuery, queue: queue) { result in
            switch result {
            case .failure(let error): completion(.failure(.fetchFailed(reason: "Failed to fetch insights. \(error.localizedDescription)")))
            case .success(let events):
                let eventsByDay = self.groupEventsByDate(events: events, after: query.start, before: query.end)
                let valuesByDay = eventsByDay.map(dailyAggregator)
                completion(.success(valuesByDay))
            }
        }
    }
}
