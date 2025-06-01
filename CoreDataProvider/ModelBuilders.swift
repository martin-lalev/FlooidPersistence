//
//  File.swift
//  
//
//  Created by Martin Lalev on 31/03/2024.
//

import Foundation
import CoreData

public func makeEntity(
    name: String,
    @FlooidPersistenceResultBuilder<NSAttributeDescription> properties: @escaping () -> [NSAttributeDescription]
) -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = name
    entity.managedObjectClassName = ""
    entity.properties = properties()
    return entity
}

public func makeAttribute(
    name: String,
    type: NSAttributeDescription.AttributeType,
    optional: Bool,
    defaultValue: Any? = nil
) -> NSAttributeDescription {
    let attribute = NSAttributeDescription()
    attribute.name = name
    attribute.type = type
    attribute.isOptional = optional
    attribute.defaultValue = defaultValue
    return attribute
}

public extension NSEntityDescription {
    func relate(
        to entity: NSEntityDescription,
        named name: String,
        maxCount: Int,
        deleteRule: NSDeleteRule = .cascadeDeleteRule
    ) {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = entity
        relationship.maxCount = maxCount
        relationship.deleteRule = deleteRule
        self.properties.append(relationship)
    }
}
