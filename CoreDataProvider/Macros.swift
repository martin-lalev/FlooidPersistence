//
//  File.swift
//  
//
//  Created by Martin Lalev on 30/03/2024.
//

import Foundation

@attached(peer, names: suffixed(PredicateBuilder), suffixed(SortBuilder))
public macro PersistedEntity() = #externalMacro(module: "FlooidCoreDataMacros", type: "PersistenceClientModelMacro")

@attached(peer, names: suffixed(Service), suffixed(ServiceClient), suffixed(CoreDataConfiguration))
public macro PersistenceService(_ modelName: String) = #externalMacro(module: "FlooidCoreDataMacros", type: "PersistenceClientServiceMacro")

@attached(member, names: named(PredicateBuilder), named(SortBuilder), named(mapper), named(entityName), named(update))
public macro Entity() = #externalMacro(module: "FlooidCoreDataMacros", type: "PersistenceClientModelMemberMacro")

