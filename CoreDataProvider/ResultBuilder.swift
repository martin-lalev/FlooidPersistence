//
//  FlooidPersistenceResultBuilder.swift
//  
//
//  Created by Martin Lalev on 01/06/2025.
//

@resultBuilder
public enum FlooidPersistenceResultBuilder<Element> {
    public static func buildBlock(_ components: [Element] ...) -> [Element] { components.flatMap { $0 } }
    
    public static func buildIf(_ component: [Element]?) -> [Element] { component ?? [] }
    
    public static func buildEither(first: [Element]) -> [Element] { first }

    public static func buildEither(second: [Element]) -> [Element] { second }

    public static func buildArray(_ components: [Element]) -> [Element] { components }

    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }

    public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }

    public static func buildExpression(_ expression: [Element]) -> [Element] { expression }

    public static func buildExpression(_ expression: Element) -> [Element] { [expression] }

    public static func buildExpression(_ expression: Element?) -> [Element] { expression.map { [$0] } ?? [] }

    public static func buildExpression(_ expression: ()) -> [Element] { [] }
}
