//
//  Repository.swift
//  DandaniaCoreDataProvider
//
//  Created by Martin Lalev on 24.08.18.
//  Copyright © 2018 Martin Lalev. All rights reserved.
//

import Foundation
import CoreData

public enum CoreDataLocation {
    case inMemory
    case disk(baseURL: URL? = nil)
    
    func storeURL(for modelName: String) -> URL? {
        switch self {
        case .inMemory:
            URL(fileURLWithPath: "/dev/null")
        case .disk(let baseURL):
            if let storeURL = baseURL?.appendingPathComponent("\(modelName).sqlite") {
                storeURL
            } else {
                nil
            }
        }
    }
}

public final class CoreDataConfiguration: Sendable {
    fileprivate let container: NSPersistentContainer
    public convenience init(modelName: String, bundle: Bundle? = Bundle.main, location: CoreDataLocation) {
        guard let modelURL = bundle?.url(forResource: modelName, withExtension: "momd") else {
            fatalError("Unable to Find Data Model")
        }
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Unable to Load Data Model")
        }
        self.init(modelName: modelName, location: location, managedObjectModel: managedObjectModel)
    }
    
    public convenience init(
        modelName: String,
        location: CoreDataLocation,
        entities: @escaping () -> [NSEntityDescription]
    ) {
        let managedObjectModel = NSManagedObjectModel()
        managedObjectModel.entities = entities()
        self.init(modelName: modelName, location: location, managedObjectModel: managedObjectModel)
    }
    
    init(
        modelName: String,
        location: CoreDataLocation,
        managedObjectModel: NSManagedObjectModel
    ) {
        container = NSPersistentContainer(name: modelName, managedObjectModel: managedObjectModel)

        if let storeURL = location.storeURL(for: modelName) {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                print("Unresolved error \(error)")
            }
        }
    }
}

public extension CoreDataConfiguration {
    func makeQuery<Entity, QB: ObjectPredicate, QS: ObjectSorter>(
        entityName: String,
        filter: [NSPredicate],
        sort: [NSSortDescriptor],
        mapper: @escaping (NSManagedObject) -> Entity?
    ) -> some QueryExecuter<Entity> {
        EntityQueryExecuter(
            entityName: entityName,
            filter: filter,
            sort: sort,
            mapper: mapper,
            context: newBackgroundContext()
        )
    }
    
    func addOrUpdate<E: Identifiable<String>>(
        _ entities: [E],
        entityName: String,
        update: @escaping (_ model: NSManagedObject, _ entity: E, _ context: NSManagedObjectContext) -> Void
    ) async {
        await executeInBackground { context in
            let predicate = ObjectPredicate(key: "", isArray: false).string("id").isIn(entities.map { $0.id })
            let fetchRequest = context.makeFetchRequest(for: entityName, predicates: [predicate], sortDescriptors: [])
            let prefetched = try? context.fetch(fetchRequest)
            
            for entity in entities {
                let existing = prefetched?.first(where: { ($0.value(forKey: "id") as? String) == entity.id })
                let result = existing ?? NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
                update(result, entity, context)
            }
            if context.hasChanges {
                try? context.save()
            }
        }
    }
}

private extension CoreDataConfiguration {
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = self.container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    func executeInBackground(_ action: @escaping (NSManagedObjectContext) -> Void) async {
        let context = newBackgroundContext()
        await withCheckedContinuation { continuation in
            context.perform {
                action(context)
                if context.hasChanges {
                    try? context.save()
                }
                continuation.resume()
            }
        }
    }
}
