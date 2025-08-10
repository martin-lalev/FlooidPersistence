//
//  File.swift
//  
//
//  Created by Martin Lalev on 31/03/2024.
//

import Foundation
import Combine
import CoreData

public protocol QueryExecuter<Entity> {
    associatedtype Entity
    func execute() -> [Entity]
    func resultsPublisher() -> AnyPublisher<[Entity], Never>
    func updatesPublisher() -> AnyPublisher<[Entity], Never>
    func subscribeToResults(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol
    func subscribeToUpdates(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol
    func deleteAll()
}

struct AnyQueryExecuter<Entity>: QueryExecuter {
    let _execute: () -> [Entity]
    let _resultsPublisher: () -> AnyPublisher<[Entity], Never>
    let _updatesPublisher: () -> AnyPublisher<[Entity], Never>
    let _subscribeToResults: (_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol
    let _subscribeToUpdates: (_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol
    let _deleteAll: () -> Void
    
    init(
        execute: @escaping () -> [Entity],
        resultsPublisher: @escaping () -> AnyPublisher<[Entity], Never>,
        updatesPublisher: @escaping () -> AnyPublisher<[Entity], Never>,
        subscribeToResults: @escaping (_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol,
        subscribeToUpdates: @escaping (_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol,
        deleteAll: @escaping () -> Void
    ) {
        self._execute = execute
        self._resultsPublisher = resultsPublisher
        self._updatesPublisher = updatesPublisher
        self._subscribeToResults = subscribeToResults
        self._subscribeToUpdates = subscribeToUpdates
        self._deleteAll = deleteAll
    }

    func execute() -> [Entity] {
        self._execute()
    }
    func resultsPublisher() -> AnyPublisher<[Entity], Never> {
        self._resultsPublisher()
    }
    func updatesPublisher() -> AnyPublisher<[Entity], Never> {
        self._updatesPublisher()
    }
    func subscribeToResults(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol {
        self._subscribeToResults(observation)
    }
    func subscribeToUpdates(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol {
        self._subscribeToUpdates(observation)
    }
    func deleteAll() {
        self._deleteAll()
    }
}

final class EntityQueryExecuter<Entity>: NSObject, @unchecked Sendable, NSFetchedResultsControllerDelegate, QueryExecuter {
    private let entityName: String
    private let filter: [NSPredicate]
    private let sort: [NSSortDescriptor]
    private let mapper: (NSManagedObject) -> Entity?
    private let context: NSManagedObjectContext
    
    var objects:[NSManagedObject] {
        return self.results.fetchedObjects ?? []
    }
    private let results:NSFetchedResultsController<NSManagedObject>
    private let notificationName: Notification.Name

    init(
        entityName: String,
        filter: [NSPredicate],
        sort: [NSSortDescriptor],
        mapper: @escaping (NSManagedObject) -> Entity?,
        context: NSManagedObjectContext
    ) {
        let fetchRequest = context.makeFetchRequest(for: entityName, predicates: filter, sortDescriptors: sort)
        self.entityName = entityName
        self.filter = filter
        self.sort = sort
        self.mapper = mapper
        self.context = context
        self.notificationName = Notification.Name(UUID().uuidString)
        self.results = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)

        super.init()
        
        self.results.delegate = self
        try? self.results.performFetch()
    }
    
    func resultsPublisher() -> AnyPublisher<[Entity], Never> {
        self.results
            .publisher(for: \.fetchedObjects)
            .map { [mapper] in $0?.compactMap { [mapper] in mapper($0) } ?? [] }
            .eraseToAnyPublisher()
    }

    func updatesPublisher() -> AnyPublisher<[Entity], Never> {
        Just([]).merge(with: objectsDidChangePublisher())
            .eraseToAnyPublisher()
    }

    private func asFetchRequest() -> NSFetchRequest<NSManagedObject> {
        self.context.makeFetchRequest(for: entityName, predicates: filter, sortDescriptors: sort)
    }
    
    func execute() -> [Entity] {
        ((try? self.context.fetch(self.asFetchRequest())) ?? []).compactMap(mapper)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        NotificationCenter.default.post(name: notificationName, object: self, userInfo: ["value": objects])
    }
    func subscribeToResults(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: notificationName, object: self, queue: nil) { [self] notification in
            guard let value = notification.userInfo?["value"] else { return }
            guard let value = value as? [NSManagedObject] else { return }
            observation(value.compactMap(mapper))
        }
    }
    
    func deleteAll() {
        for item in (try? self.context.fetch(self.asFetchRequest())) ?? [] {
            self.context.delete(item)
        }
    }

    func subscribeToUpdates(_ observation: @Sendable @escaping ([Entity]) -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange, object: self, queue: nil) { [self] notification in
            observation(mapContextObjectsDidChange(notification: notification))
        }
    }

    private func objectsDidChangePublisher() -> some Publisher<[Entity], Never> {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .map { [self] notification in
                mapContextObjectsDidChange(notification: notification)
            }
    }
    private func mapContextObjectsDidChange(notification: Notification) -> [Entity] {
            // let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>
            let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>
            let refreshed = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject>

            let objectsSet = [refreshed, updated]
                .compactMap { $0 }
                .reduce(Set()) { $0.union($1) }
                .filter { $0.entity.name == entityName }
            
            let objects = Array(objectsSet)
            let predicated = NSArray(array: objects).filtered(using: NSCompoundPredicate(andPredicateWithSubpredicates: filter))
            let sorted = NSArray(array: predicated).sortedArray(using: sort)
            let result = sorted.compactMap { $0 as? NSManagedObject }
            
            return result.compactMap(mapper)
    }
}

extension NSManagedObjectContext {
    func makeFetchRequest<T: NSManagedObject>(for entityName: String, predicates: [NSPredicate], sortDescriptors: [NSSortDescriptor]) -> NSFetchRequest<T> {
        let fetchRequest = NSFetchRequest<T>.init(entityName: entityName)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.sortDescriptors = sortDescriptors
        return fetchRequest
    }
}
