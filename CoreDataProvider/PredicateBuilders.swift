//
//  Object.swift
//  DandaniaCoreDataProvider
//
//  Created by Martin Lalev on 24.08.18.
//  Copyright © 2018 Martin Lalev. All rights reserved.
//

import Foundation

public prefix func !(other: NSPredicate) -> NSPredicate {
    return NSCompoundPredicate(notPredicateWithSubpredicate: other)
}
public extension NSPredicate {
    static func && (left: NSPredicate, right: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [left, right])
    }
    static func || (left: NSPredicate, right: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: [left, right])
    }
}

public func and(@FlooidPersistenceResultBuilder<NSPredicate> _ maker: () -> [NSPredicate]) -> NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: maker())
}

public func or(@FlooidPersistenceResultBuilder<NSPredicate> _ maker: () -> [NSPredicate]) -> NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: maker())
}

public final class BoolPredicate {
    let key: String
    let isArray: Bool
    let placeholder: String

    init(key: String, isArray: Bool, placeholder: String) {
        self.key = key
        self.isArray = isArray
        self.placeholder = placeholder
    }

    private var fullKey: String { self.isArray ? "ANY " + key : key }

    public var isTrue: NSPredicate {
        NSPredicate(format: "\(fullKey) == 1")
    }
    public var isFalse: NSPredicate {
        NSPredicate(format: "\(fullKey) == 0 OR \(fullKey) == nil")
    }
    public func equals(_ value: Bool) -> NSPredicate {
        return value ? isTrue : isFalse
    }
}
public final class ValuePredicate<Value: CVarArg> {
    let key: String
    let isArray: Bool
    let placeholder: String
    
    init(key: String, isArray: Bool, placeholder: String) {
        self.key = key
        self.isArray = isArray
        self.placeholder = placeholder
    }
    
    private var fullKey: String { self.isArray ? "ANY " + key : key }

    public func equals(_ value: Value) -> NSPredicate {
        NSPredicate(format: "\(fullKey) == %\(placeholder)", value)
    }
    public func isIn(_ value: [Value]) -> NSPredicate {
        return NSPredicate(format: "\(fullKey) IN %\(placeholder)", value)
    }
    public func contains(_ value: Value) -> NSPredicate {
        return NSPredicate(format: "\(fullKey) CONTAINS[cd] %\(placeholder)", value)
    }
    public func isNil() -> NSPredicate {
        NSPredicate(format: "\(fullKey) == nil")
    }
}
public extension ValuePredicate {
    static func == (left: ValuePredicate<Value>, right: Value) -> NSPredicate {
        left.equals(right)
    }
    static func != (left: ValuePredicate<Value>, right: Value) -> NSPredicate {
        !(left == right)
    }
}
public extension BoolPredicate {
    static func == (left: BoolPredicate, right: Bool) -> NSPredicate {
        left.equals(right)
    }
    static func != (left: BoolPredicate, right: Bool) -> NSPredicate {
        !(left == right)
    }
}
open class ObjectPredicate {
    let key: String
    let isArray: Bool
    var prefix: String { self.key + (self.key.isEmpty ? "" : ".") }
    
    public required init(key: String, isArray: Bool) {
        self.key = key
        self.isArray = isArray
    }
    
    public func bool(_ key: String, array: Bool = false) -> BoolPredicate {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "@")
    }

    public func string(_ key: String, array: Bool = false) -> ValuePredicate<String> {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "@")
    }
    
    public func date(_ key: String, array: Bool = false) -> ValuePredicate<NSDate> {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "@")
    }
    
    public func int(_ key: String, array: Bool = false) -> ValuePredicate<Int> {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "i")
    }
    
    public func float(_ key: String, array: Bool = false) -> ValuePredicate<Float> {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "f")
    }
    
    public func double(_ key: String, array: Bool = false) -> ValuePredicate<Double> {
        .init(key: self.prefix + key, isArray: array || self.isArray, placeholder: "f")
    }

    public func object<O: ObjectPredicate>(_ key: String, array: Bool = false) -> O {
        .init(key: self.prefix + key, isArray: array || self.isArray)
    }
}

public struct ValueSorter {
    let key: String
    
    public func make(ascending: Bool = true) -> NSSortDescriptor {
        NSSortDescriptor(key: self.key, ascending: ascending)
    }

    public var ascending: NSSortDescriptor {
        self.make(ascending: true)
    }
    
    public var descending: NSSortDescriptor {
        self.make(ascending: false)
    }
}
open class ObjectSorter {
    let key: String
    var prefix: String { self.key + (self.key.isEmpty ? "" : ".") }
    
    public required init(key: String) {
        self.key = key
    }
    
    public func sort(_ key: String) -> ValueSorter {
        ValueSorter(key: self.prefix + key)
    }

    public func object<O: ObjectSorter>(_ key: String) -> O {
        .init(key: self.prefix + key)
    }
}
