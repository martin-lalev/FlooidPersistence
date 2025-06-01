//
//  Context.swift
//  DandaniaCoreDataProvider
//
//  Created by Martin Lalev on 24.08.18.
//  Copyright © 2018 Martin Lalev. All rights reserved.
//

import Foundation
import CoreData

public extension NSManagedObject {
    func store<V: Hashable>(
        value items: [V],
        forKey key: String,
        in context: NSManagedObjectContext,
        entityName: String,
        mapper: @escaping (NSManagedObject) -> V,
        update: @escaping (NSManagedObject, V) -> Void,
        deleteOld: Bool = true
    ) {
        let oldItems = self.mutableSetValue(forKey: key).allObjects.compactMap { $0 as? NSManagedObject }
        let oldValues = oldItems.map { mapper($0) }
        
        guard oldValues != items else { return }
        
        let newItems = items.compactMap { item -> NSManagedObject in
            let result = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
            update(result, item)
            return result
        }
        
        self.mutableSetValue(forKey: key).removeAllObjects()
        self.mutableSetValue(forKey: key).addObjects(from: newItems)
        
        guard deleteOld else { return }
        for oldItem in oldItems {
            oldItem.delete()
        }
    }
    
    func store<V: Hashable>(
        value: V?,
        forKey key: String,
        in context: NSManagedObjectContext,
        entityName: String,
        mapper: @escaping (NSManagedObject) -> V,
        update: @escaping (NSManagedObject, V) -> Void,
        deleteOld: Bool = true
    )  {
        let oldItem = self.value(forKey: key) as? NSManagedObject
        let oldValue = oldItem.map { mapper($0) }
        
        guard oldValue != value else { return }
        
        let newValue = value.map { item -> NSManagedObject in
            let result = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
            update(result, item)
            return result
        }

        self.setValue(newValue, forKey: key)
        
        guard deleteOld else { return }
        oldItem?.delete()
    }
}

extension NSManagedObject {
    func delete() {
        managedObjectContext?.delete(self)
    }
}
