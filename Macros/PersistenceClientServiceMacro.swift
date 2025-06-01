//
//  File.swift
//  
//
//  Created by Martin Lalev on 28/03/2024.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

struct PersistenceClientServiceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDeclaration = declaration.as(EnumDeclSyntax.self) else { return [] }
        
        return [
            try buildSchemaMaker(descriptorName: enumDeclaration.name.text, enumDeclaration: enumDeclaration),
            try buildService(descriptorName: enumDeclaration.name.text, enumDeclaration: enumDeclaration),
            try buildServiceClient(descriptorName: enumDeclaration.name.text, enumDeclaration: enumDeclaration),
        ].compactMap { $0 }
    }
    
    private static func buildSchemaMaker(descriptorName: String, enumDeclaration: EnumDeclSyntax) throws -> DeclSyntax? {
        let entityDeclarationSchemas = try enumDeclaration.memberBlock.members
            .flatMap { try buildEntityDeclarationSchema(declaration: $0.decl) }

        let entityStatementSchemas = try enumDeclaration.memberBlock.members
            .flatMap { try buildEntitySchemaStatement(declaration: $0.decl) }

        let relationshipDeclarations = try enumDeclaration.memberBlock.members
            .flatMap { try buildEntityRelationships(declaration: $0.decl) }

        guard let macroAttribute = enumDeclaration.attributes.first?.as(AttributeSyntax.self) else {
            return nil
        }
        guard let macroAttributeArguments = macroAttribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        guard let modelNameArgument = macroAttributeArguments.first?.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }

        let schemaConfigFunctionCall = FunctionCallExprSyntax(callee: ExprSyntax("CoreDataConfiguration")) {
            LabeledExprSyntax(label: "modelName", expression: modelNameArgument)
            LabeledExprSyntax(label: "location", expression: ExprSyntax("location"))
        }.with(\.trailingClosure, ClosureExprSyntax(statements: CodeBlockItemListSyntax {
            for entityDeclarationSchema in entityDeclarationSchemas {
                CodeBlockItemSyntax(
                    item: CodeBlockItemSyntax.Item.decl(entityDeclarationSchema)
                )
            }
            
            for relationshipDeclaration in relationshipDeclarations {
                CodeBlockItemSyntax(
                    item: CodeBlockItemSyntax.Item.expr(relationshipDeclaration)
                )
            }
            
            ReturnStmtSyntax(expression: ArrayExprSyntax(elements: ArrayElementListSyntax(itemsBuilder: {
                for entityStatementSchema in entityStatementSchemas {
                    ArrayElementSyntax(expression: entityStatementSchema)
                }
            })))
//            for entityStatementSchema in entityStatementSchemas {
//                CodeBlockItemSyntax(
//                    item: CodeBlockItemSyntax.Item.expr(entityStatementSchema)
//                )
//            }
        }))
        let schemaDeclSyntax = VariableDeclSyntax(bindingSpecifier: "let", bindings: PatternBindingListSyntax {
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: "configuration"),
                initializer: InitializerClauseSyntax(value: schemaConfigFunctionCall)
            )
        }).as(DeclSyntax.self)

        let schemaMaker = FunctionDeclSyntax(
            name: "\(raw: descriptorName)CoreDataConfiguration",
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax(itemsBuilder: {
                        FunctionParameterSyntax(
                            firstName: .wildcardToken(),
                            secondName: "location",
                            type: IdentifierTypeSyntax(name: "CoreDataLocation")
                        )
                    })
                ),
                returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "CoreDataConfiguration"))
            ),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(itemsBuilder: {
                if let schemaDeclSyntax {
                    CodeBlockItemSyntax(
                        item: CodeBlockItemSyntax.Item.decl(schemaDeclSyntax)
                    )
                }
                ReturnStmtSyntax(expression: ExprSyntax("configuration"))
            }))
        )
        
        return schemaMaker.as(DeclSyntax.self)
    }
    
    private static func buildService(descriptorName: String, enumDeclaration: EnumDeclSyntax) throws -> DeclSyntax? {
        let queryProtocols = try enumDeclaration.memberBlock.members
            .flatMap { try buildQueryProtocol(descriptorName: descriptorName, declaration: $0.decl) }
        
        let genericQueryProtocols = try enumDeclaration.memberBlock.members
            .flatMap { try buildGenericQueryProtocol(descriptorName: descriptorName, declaration: $0.decl) }
        
        let addOrUpdateProtocols = try enumDeclaration.memberBlock.members
            .flatMap { try buildAddOrUpdateProtocol(descriptorName: descriptorName, declaration: $0.decl) }
        
        let protocolBuilder = try ProtocolDeclSyntax("protocol \(raw: descriptorName)Service: Sendable") {
            for decl in queryProtocols {
                decl
            }
            
            for decl in genericQueryProtocols {
                decl
            }
            
            for decl in addOrUpdateProtocols {
                decl
            }
        }.as(DeclSyntax.self)
        
        return protocolBuilder
    }
    
    private static func buildServiceClient(descriptorName: String, enumDeclaration: EnumDeclSyntax) throws -> DeclSyntax? {
        let queryImplementations = try enumDeclaration.memberBlock.members
            .flatMap { try buildQueryImplementation(descriptorName: descriptorName, declaration: $0.decl) }
        
        let genericQueryImplementations = try enumDeclaration.memberBlock.members
            .flatMap { try buildGenericQueryImplementation(descriptorName: descriptorName, declaration: $0.decl) }
        
        let addOrUpdateImplementations = try enumDeclaration.memberBlock.members
            .flatMap { try buildAddOrUpdateImplementation(descriptorName: descriptorName, declaration: $0.decl) }
        
        let clientBuilder = try ClassDeclSyntax("final class \(raw: descriptorName)ServiceClient: \(raw: descriptorName)Service") {
            DeclSyntax("private let configuration: CoreDataConfiguration")
            DeclSyntax("init(configuration: CoreDataConfiguration) { self.configuration = configuration }").with(\.leadingTrivia, .newlines(2))
            
            for decl in queryImplementations {
                decl
            }
            
            for decl in genericQueryImplementations {
                decl
            }
            
            for decl in addOrUpdateImplementations {
                decl
            }
        }.as(DeclSyntax.self)
        
        return clientBuilder
    }
    
    private static func buildEntityDeclarationSchema(declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let attributes = structDeclaration.memberBlock.members
            .compactMap { try? implementAttribute(declaration: $0.decl)?.as(ExprSyntax.self) }
        
        let entityName = structDeclaration.name.text
        let modelName = entityName.replacingOccurrences(of: "Entity", with: "")
        
        let functionCallExpression = FunctionCallExprSyntax(callee: ExprSyntax("makeEntity")) {
            LabeledExprSyntax(label: "name", expression: ExprSyntax("\"\(raw: modelName)\""))
        }.with(\.trailingClosure, ClosureExprSyntax(statements: CodeBlockItemListSyntax {
            for attribute in attributes {
                attribute
            }
        }))
        
        let entityDeclaration = VariableDeclSyntax(bindingSpecifier: "let", bindings: PatternBindingListSyntax {
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: "entity\(raw: modelName)"),
                initializer: InitializerClauseSyntax(value: functionCallExpression)
            )
        })

        return [entityDeclaration.as(DeclSyntax.self)].compactMap { $0 }
    }
    
    private static func buildEntitySchemaStatement(declaration: DeclSyntax) throws -> [ExprSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let entityName = structDeclaration.name.text
        let modelName = entityName.replacingOccurrences(of: "Entity", with: "")
        
        return [ExprSyntax("entity\(raw: modelName)")]
    }

    private static func buildAddOrUpdateProtocol(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let isIdentifiable = structDeclaration.inheritanceClause?.inheritedTypes.contains(where: { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }) ?? false
        
        guard isIdentifiable else {
            return []
        }
        
        let entityName = structDeclaration.name.text

        let addOrUpdateDeclaration = try FunctionDeclSyntax("func addOrUpdate(_ entities: [\(raw: descriptorName).\(raw: entityName)]) async")
        
        return addOrUpdateDeclaration.as(DeclSyntax.self).map { [$0] } ?? []
    }

    private static func buildAddOrUpdateImplementation(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let isIdentifiable = structDeclaration.inheritanceClause?.inheritedTypes.contains(where: { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }) ?? false
        
        guard isIdentifiable else {
            return []
        }
        
        let entityName = structDeclaration.name.text

        let addOrUpdateDeclaration = try FunctionDeclSyntax("func addOrUpdate(_ entities: [\(raw: descriptorName).\(raw: entityName)]) async") {
            CodeBlockItemSyntax(
"""
            await configuration.addOrUpdate(
                entities,
                entityName: \(raw: descriptorName).\(raw: entityName).entityName(),
                update: { model, entity, context in
                    entity.update(model, in: context)
                }
            )
"""
)
        }
        
        return addOrUpdateDeclaration.as(DeclSyntax.self).map { [$0] } ?? []
    }

    private static func buildGenericQueryProtocol(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let isIdentifiable = structDeclaration.inheritanceClause?.inheritedTypes.contains(where: { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }) ?? false
        
        guard isIdentifiable else {
            return []
        }
        
        let entityName = structDeclaration.name.text

        let addOrUpdateDeclaration = try FunctionDeclSyntax(
"""
func query(
    @FlooidPersistenceResultBuilder<NSPredicate> _ makeFilter: @escaping (\(raw: descriptorName).\(raw: entityName).PredicateBuilder) -> [NSPredicate],
    @FlooidPersistenceResultBuilder<NSSortDescriptor> sort: @escaping (\(raw: descriptorName).\(raw: entityName).SortBuilder) -> [NSSortDescriptor]
) -> any QueryExecuter<\(raw: descriptorName).\(raw: entityName)>
""")
        
        return addOrUpdateDeclaration.as(DeclSyntax.self).map { [$0] } ?? []
    }

    private static func buildGenericQueryImplementation(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let isIdentifiable = structDeclaration.inheritanceClause?.inheritedTypes.contains(where: { inheritedType in
            inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }) ?? false
        
        guard isIdentifiable else {
            return []
        }
        
        let entityName = structDeclaration.name.text

        let queryCallExpr = FunctionCallExprSyntax(
            callee: MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("configuration")),
                declName: DeclReferenceExprSyntax(baseName: .identifier("makeQuery"))
            )
        ) {
            LabeledExprSyntax(label: "entityName", expression: ExprSyntax("\(raw: descriptorName).\(raw: entityName).entityName()"))
                .with(\.leadingTrivia, .newline)
            LabeledExprSyntax(label: "filter", expression: ExprSyntax("filter(.init(key: \"\", isArray: false))"))
                .with(\.leadingTrivia, .newline)
            LabeledExprSyntax(label: "sort", expression: ExprSyntax("sort(.init(key: \"\"))"))
                .with(\.leadingTrivia, .newline)
            LabeledExprSyntax(label: "mapper", expression: ExprSyntax("\(raw: descriptorName).\(raw: entityName).mapper"))
                .with(\.leadingTrivia, .newline)
                .with(\.trailingTrivia, .newline)
        }
        let addOrUpdateDeclaration = try FunctionDeclSyntax(
"""
func query(
    @FlooidPersistenceResultBuilder<NSPredicate> _ filter: @escaping (\(raw: descriptorName).\(raw: entityName).PredicateBuilder) -> [NSPredicate],
    @FlooidPersistenceResultBuilder<NSSortDescriptor> sort: @escaping (\(raw: descriptorName).\(raw: entityName).SortBuilder) -> [NSSortDescriptor]
) -> any QueryExecuter<\(raw: descriptorName).\(raw: entityName)>
""") {
    if let queryCallExpr = queryCallExpr.as(ExprSyntax.self) {
        CodeBlockItemSyntax(item: .expr(queryCallExpr))
    }
        }
        
        return addOrUpdateDeclaration.as(DeclSyntax.self).map { [$0] } ?? []
    }

    private static func buildEntityRelationships(declaration: DeclSyntax) throws -> [ExprSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        guard let memberType = structDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Entity" else {
            return []
        }
        
        let entityName = structDeclaration.name.text

        let relationshipStatements = structDeclaration.memberBlock.members
            .compactMap { implementRelationship(entityName: entityName, declaration: $0.decl) }
        
        return relationshipStatements
    }
    
    private static func buildQueryProtocol(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else { return [] }
        
        guard let memberType = functionDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Query" else {
            return []
        }
        
        guard let queryType = functionDeclaration.signature.returnClause?.type.as(MemberTypeSyntax.self)?.baseType.as(IdentifierTypeSyntax.self) else {
            return []
        }
        let entityName = queryType.name.text
        
        let returnClause = ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "any QueryExecuter<\(raw: descriptorName).\(raw: entityName)>"))
        let newSignature = functionDeclaration.signature
            .with(\.returnClause, returnClause)
        
        let function = functionDeclaration.with(\.attributes, [])
            .with(\.signature, newSignature)
            .with(\.modifiers, DeclModifierListSyntax { })
            .with(\.body, nil)
        return [function.as(DeclSyntax.self)].compactMap { $0 }
    }
    
    private static func buildQueryImplementation(descriptorName: String, declaration: DeclSyntax) throws -> [DeclSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else { return [] }

        guard let memberType = functionDeclaration.attributes.first?.as(AttributeSyntax.self)?.attributeName.description else {
            return []
        }
        guard memberType == "Query" else {
            return []
        }
        
        guard let queryType = functionDeclaration.signature.returnClause?.type.as(MemberTypeSyntax.self)?.baseType.as(IdentifierTypeSyntax.self) else {
            return []
        }
        let entityName = queryType.name.text
        
        let queryFuncParams = functionDeclaration.signature.parameterClause.parameters.map { $0 }

        let functionCallExperession = FunctionCallExprSyntax(callee: "\(raw: descriptorName).\(functionDeclaration.name)" as ExprSyntax) {
            for param in queryFuncParams {
                let paramName = param.firstName.text
                let paramValue = param.secondName?.text ?? param.firstName.text
                LabeledExprSyntax(label: paramName, expression: ExprSyntax("\(raw: paramValue)"))
            }
        }
        
        let returnClause = ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "any QueryExecuter<\(raw: descriptorName).\(raw: entityName)>"))
        let newSignature = functionDeclaration.signature
            .with(\.returnClause, returnClause)

        let function = functionDeclaration.with(\.attributes, [])
            .with(\.signature, newSignature)
            .with(\.modifiers, DeclModifierListSyntax { })
            .with(\.leadingTrivia, .newlines(2))
            .with(\.body, CodeBlockSyntax(statements: CodeBlockItemListSyntax(itemsBuilder: {
                DeclSyntax("let entityName = \(raw: descriptorName).\(raw: entityName).entityName()")
                VariableDeclSyntax(bindingSpecifier: "let", bindings: PatternBindingListSyntax {
                    PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: "queryMaker"),
                        initializer: InitializerClauseSyntax(value: functionCallExperession)
                    )
                })
                DeclSyntax("let converting = \(raw: descriptorName).\(raw: entityName).mapper")
                "return configuration.makeQuery(entityName: entityName, filter: queryMaker.makeFilter(), sort: queryMaker.makeSorter(), mapper: converting)"
            })))
        return [function.as(DeclSyntax.self)].compactMap { $0 }
    }
}

struct PersistenceClientModelMemberMacro: MemberMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            return []
        }
        
        let entityName = structDeclaration.name.text
        
        return [
            try buildEntityName(entityName: entityName, structDeclaration: structDeclaration),
            try buildPredicate(entityName: entityName, structDeclaration: structDeclaration),
            try buildSorter(entityName: entityName, structDeclaration: structDeclaration),
            try buildMapper(entityName: entityName, structDeclaration: structDeclaration),
            try buildUpdate(entityName: entityName, structDeclaration: structDeclaration),
        ].compactMap { $0 }
    }
    
    private static func buildEntityName(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        return DeclSyntax("static func entityName() -> String { \"\(raw: entityName.replacingOccurrences(of: "Entity", with: ""))\" }").with(\.leadingTrivia, .newlines(2))
    }
    
    // TODO: Implement proper mapping
    private static func buildMapper(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let arguments = structDeclaration.memberBlock.members
            .compactMap { try? implementPropertyMapping(declaration: $0.decl) }
        
        let initCall = FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: "Self")) {
            for argument in arguments {
                argument
            }
        }
        
        return try FunctionDeclSyntax("static func mapper(_ model: NSManagedObject) -> Self?") {
            if let initCall = initCall.as(ExprSyntax.self) {
                CodeBlockItemSyntax(item: .expr(initCall))
            }
        }.as(DeclSyntax.self)
    }
    
    private static func buildPredicate(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let protocolImplementations = structDeclaration.memberBlock.members
            .compactMap { try? implementPredicate(declaration: $0.decl, dotReference: true) }
        let predicateBuilder = try ClassDeclSyntax("class PredicateBuilder: ObjectPredicate") {
            for implementedFunction in protocolImplementations {
                implementedFunction
            }
        }
        return predicateBuilder.as(DeclSyntax.self)
    }
    
    private static func buildSorter(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let protocolImplementations = structDeclaration.memberBlock.members
            .compactMap { try? implementSorter(declaration: $0.decl, dotReference: true) }
        let predicateBuilder = try ClassDeclSyntax("class SortBuilder: ObjectSorter") {
            for implementedFunction in protocolImplementations {
                implementedFunction
            }
        }
        return predicateBuilder.as(DeclSyntax.self)
    }
    
    private static func buildUpdate(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let assignemnts = structDeclaration.memberBlock.members
            .compactMap { try? implementAssigner(declaration: $0.decl) }
        
        let updateDeclaration = try FunctionDeclSyntax("func update(_ model: NSManagedObject, in context: NSManagedObjectContext)") {
            for assignemnt in assignemnts {
                for item in assignemnt {
                    CodeBlockItemSyntax(item: item)
                }
            }
        }
        return updateDeclaration.as(DeclSyntax.self)
    }
}

struct PersistenceClientModelMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            return []
        }
        
        let entityName = structDeclaration.name.text
        
        return [
            try buildPredicate(entityName: entityName, structDeclaration: structDeclaration),
            try buildSorter(entityName: entityName, structDeclaration: structDeclaration)
        ].compactMap { $0 }
    }
    
    private static func buildPredicate(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let protocolImplementations = structDeclaration.memberBlock.members
            .compactMap { try? implementPredicate(declaration: $0.decl) }
        let predicateBuilder = try ClassDeclSyntax("class \(raw: entityName)PredicateBuilder: ObjectPredicate") {
            for implementedFunction in protocolImplementations {
                implementedFunction
            }
        }
        return predicateBuilder.as(DeclSyntax.self)
    }
    
    private static func buildSorter(entityName: String, structDeclaration: StructDeclSyntax) throws -> DeclSyntax? {
        let protocolImplementations = structDeclaration.memberBlock.members
            .compactMap { try? implementSorter(declaration: $0.decl) }
        let predicateBuilder = try ClassDeclSyntax("class \(raw: entityName)SortBuilder: ObjectSorter") {
            for implementedFunction in protocolImplementations {
                implementedFunction
            }
        }
        return predicateBuilder.as(DeclSyntax.self)
    }
}

struct ParsedVariable {
    let identifierSyntax: IdentifierPatternSyntax
    let isArray: Bool
    let isOptional: Bool
    let rawType: TypeSyntax
    let underlyingType: IdentifierTypeSyntax
    init?(for variableDeclaration: VariableDeclSyntax) {
        guard let patternBinding = variableDeclaration.bindings.first?.as(PatternBindingSyntax.self) else { return nil }
        
        guard let identifierSyntax = patternBinding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        guard let typeSyntax = patternBinding.typeAnnotation?.as(TypeAnnotationSyntax.self) else { return nil }
        
        self.rawType = typeSyntax.type
        
        var isArray = false
        var isOptional = false
        var underlyingType: IdentifierTypeSyntax?
        if let arrayType = typeSyntax.type.as(ArrayTypeSyntax.self) {
            if let wrapepdType = arrayType.element.as(IdentifierTypeSyntax.self) {
                isArray = true
                underlyingType = wrapepdType
            }
        } else if let optionalType = typeSyntax.type.as(OptionalTypeSyntax.self) {
            isOptional = true
            if let arrayType = optionalType.wrappedType.as(ArrayTypeSyntax.self) {
                if let wrapepdType = arrayType.element.as(IdentifierTypeSyntax.self) {
                    isArray = true
                    underlyingType = wrapepdType
                }
            } else if let paramType = optionalType.wrappedType.as(IdentifierTypeSyntax.self) {
                if paramType.name.text == "Array" {
                    if let wrapped = paramType.genericArgumentClause?.arguments.first?.argument.as(IdentifierTypeSyntax.self) {
                        underlyingType = wrapped
                    }
                } else {
                    underlyingType = paramType
                }
            }
        } else if let paramType = typeSyntax.type.as(IdentifierTypeSyntax.self) {
            if paramType.name.text == "Array" {
                if let wrapped = paramType.genericArgumentClause?.arguments.first?.argument.as(IdentifierTypeSyntax.self) {
                    underlyingType = wrapped
                }
            } else {
                underlyingType = paramType
            }
        }
        
        guard let underlyingType else {
            return nil
        }
        
        self.isArray = isArray
        self.isOptional = isOptional
        self.underlyingType = underlyingType
        self.identifierSyntax = identifierSyntax
    }
}

private func implementPropertyMapping(declaration: DeclSyntax) throws -> LabeledExprSyntax? {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return nil }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return nil }
    
    let isArray = parsedVariable.isArray
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text
    
    if underlyingType.hasSuffix("Entity") {
        if isArray {
            return LabeledExprSyntax(
                label: identifierName,
                expression: ExprSyntax("model.mutableSetValue(forKey: \"\(raw: identifierName)\").allObjects.compactMap { $0 as? NSManagedObject }.compactMap(\(raw: underlyingType).mapper)")
            ).with(\.leadingTrivia, .newline)
        } else {
            if parsedVariable.isOptional {
                return LabeledExprSyntax(
                    label: identifierName,
                    expression: ExprSyntax("(model.value(forKey: \"\(raw: identifierName)\") as! NSManagedObject?).flatMap(\(raw: underlyingType).mapper)")
                ).with(\.leadingTrivia, .newline)
            } else {
                return LabeledExprSyntax(
                    label: identifierName,
                    expression: ExprSyntax("\(raw: underlyingType).mapper(model.value(forKey: \"\(raw: identifierName)\") as! NSManagedObject)!")
                ).with(\.leadingTrivia, .newline)
            }
        }
    } else {
        return LabeledExprSyntax(
            label: identifierName,
            expression: AsExprSyntax(
                expression: ExprSyntax("model.value(forKey: \"\(raw: identifierName)\")"),
                questionOrExclamationMark: .exclamationMarkToken(),
                type: parsedVariable.rawType
            )
        )
        .with(\.leadingTrivia, .newline)
    }
}

private func implementPredicate(declaration: DeclSyntax, dotReference: Bool = false) throws -> VariableDeclSyntax? {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return nil }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return nil }
    
    let isArray = parsedVariable.isArray
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text
    
    func makeVariableDeclSyntax(
        identifierName: String,
        predicateType: String,
        predicateAccess: String,
        isArray: Bool
    ) throws -> VariableDeclSyntax {
        try VariableDeclSyntax("var \(raw: identifierName): \(raw: predicateType)") {
            ExprSyntax("self.\(raw: predicateAccess)(\"\(raw: identifierName)\", array: \(raw: isArray))")
        }.with(\.leadingTrivia, .newlines(1))
    }
    
    if underlyingType.hasSuffix("Entity") {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "\(underlyingType)\(dotReference ? "." : "")PredicateBuilder",
            predicateAccess: "object",
            isArray: isArray
        )
    } else if underlyingType == "Bool" {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "BoolPredicate",
            predicateAccess: "bool",
            isArray: isArray
        )
    } else if underlyingType == "Int" {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValuePredicate<Int>",
            predicateAccess: "int",
            isArray: isArray
        )
    } else if underlyingType == "Double" {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValuePredicate<Double>",
            predicateAccess: "double",
            isArray: isArray
        )
    } else if underlyingType == "Float" {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValuePredicate<Float>",
            predicateAccess: "float",
            isArray: isArray
        )
    } else if underlyingType == "Date" {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValuePredicate<NSDate>",
            predicateAccess: "date",
            isArray: isArray
        )
    } else {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValuePredicate<String>",
            predicateAccess: "string",
            isArray: isArray
        )
    }
}

private func implementAssigner(declaration: DeclSyntax) throws -> [CodeBlockItemSyntax.Item] {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return [] }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return [] }
    
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text

    if underlyingType.hasSuffix("Entity") {
        let storeCall = FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: "model.\(raw: "store")")) {
            LabeledExprSyntax(
                label: "value",
                expression: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                    declName: DeclReferenceExprSyntax(baseName: .identifier(identifierName))
                )
            ).with(\.leadingTrivia, .newlines(1))
            LabeledExprSyntax(label: "forKey", expression: StringLiteralExprSyntax(content: identifierName)).with(\.leadingTrivia, .newlines(1))
            LabeledExprSyntax(label: "in", expression: ExprSyntax("context")).with(\.leadingTrivia, .newlines(1))
            LabeledExprSyntax(label: "entityName", expression: ExprSyntax("\(raw: underlyingType).entityName()")).with(\.leadingTrivia, .newlines(1))
            LabeledExprSyntax(label: "mapper", expression: ExprSyntax("\(raw: underlyingType).mapper")).with(\.leadingTrivia, .newlines(1))
            LabeledExprSyntax(label: "update", expression: ClosureExprSyntax(statements: CodeBlockItemListSyntax {
                CodeBlockItemSyntax(item: .expr(ExprSyntax("$1?.update($0, in: context)")))
            })).with(\.leadingTrivia, .newlines(1))
        }.as(ExprSyntax.self)
        
        return [
            storeCall.map { .expr($0) },
        ].compactMap { $0 }
    } else {
        return FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: "model.setValue")) {
            LabeledExprSyntax(expression: ExprSyntax("self.\(raw: identifierName)"))
            LabeledExprSyntax(label: "forKey", expression: StringLiteralExprSyntax(content: identifierName))
        }.as(ExprSyntax.self).map { [.expr($0)] } ?? []
    }
}

private func implementSorter(declaration: DeclSyntax, dotReference: Bool = false) throws -> VariableDeclSyntax? {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return nil }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return nil }
    
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text

    func makeVariableDeclSyntax(
        identifierName: String,
        predicateType: String,
        predicateAccess: String
    ) throws -> VariableDeclSyntax {
        try VariableDeclSyntax("var \(raw: identifierName): \(raw: predicateType)") {
            ExprSyntax("self.\(raw: predicateAccess)(\"\(raw: identifierName)\")")
        }.with(\.leadingTrivia, .newlines(1))
    }

    if underlyingType.hasSuffix("Entity") {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "\(underlyingType)\(dotReference ? "." : "")SortBuilder",
            predicateAccess: "object"
        )
    } else {
        return try makeVariableDeclSyntax(
            identifierName: identifierName,
            predicateType: "ValueSorter",
            predicateAccess: "sort"
        )
    }
}

private func implementAttribute(declaration: DeclSyntax) throws -> FunctionCallExprSyntax? {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return nil }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return nil }
    
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text

    func makeAttributeSyntax(
        identifierName: String,
        attributeType: String,
        optional: Bool = true,
        defaultValue: Any? = nil
    ) throws -> FunctionCallExprSyntax {
        FunctionCallExprSyntax(callee: ExprSyntax("makeAttribute")) {
            LabeledExprSyntax(label: "name", expression: ExprSyntax("\"\(raw: identifierName)\""))
            LabeledExprSyntax(label: "type", expression: ExprSyntax(".\(raw: attributeType)"))
            LabeledExprSyntax(label: "optional", expression: ExprSyntax("\(raw: optional)"))
            if let defaultValue {
                LabeledExprSyntax(label: "defaultValue", expression: ExprSyntax("\(raw: defaultValue)"))
            } else {
                LabeledExprSyntax(label: "defaultValue", expression: ExprSyntax("nil"))
            }
        }
    }

    //<attribute name="{{ var.name }}" optional="YES" attributeType="Transformable"                                                     valueTransformerName="NSSecureUnarchiveFromData" customClassName="{{ var.typeName }}"/>

//    {% elif var.annotations.enum %}
//            <attribute name="{{ var.name }}" optional="YES" attributeType="String"/>
//    {% elif var.annotations.enumDefault %}
//            <attribute name="{{ var.name }}" optional="YES" attributeType="String"/>
//    {% else %}
//            <attribute name="{{ var.name }}" optional="YES" attributeType="Transformable" valueTransformerName="NSSecureUnarchiveFromData" customClassName="{{ var.typeName }}"/>
//    {% endif %}

//    {% if var.typeName.isArray %}
//            <relationship name="{{ var.name }}" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="{% call linkEntityName var.typeName.array.elementTypeName.unwrappedTypeName %}"/>
//    {% else %}
//            <relationship name="{{ var.name }}" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="{% call linkEntityName var.typeName.unwrappedTypeName %}"/>
//    {% endif %}

    if underlyingType.hasSuffix("Entity") {
        return nil
    } else if underlyingType == "Bool" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "boolean")
    } else if underlyingType == "String" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "string", defaultValue: "\"\"")
    } else if underlyingType == "Float" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "float", defaultValue: 0.0)
    } else if underlyingType == "Double" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "double", defaultValue: 0.0)
    } else if underlyingType == "Date" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "date")
    } else if underlyingType == "Int" {
        return try makeAttributeSyntax(identifierName: identifierName, attributeType: "integer16", optional: false, defaultValue: 0)
    } else {
        return nil
    }
}

private func implementRelationship(entityName: String, declaration: DeclSyntax) -> ExprSyntax? {
    guard let variableDeclaration = declaration.as(VariableDeclSyntax.self) else { return nil }
    // must be not computed
    guard let parsedVariable = ParsedVariable(for: variableDeclaration) else { return nil }
    
    let underlyingType = parsedVariable.underlyingType.name.text
    let identifierName = parsedVariable.identifierSyntax.identifier.text

    if underlyingType.hasSuffix("Entity") {
        return FunctionCallExprSyntax(callee: ExprSyntax("entity\(raw: entityName.replacingOccurrences(of: "Entity", with: "")).relate")) {
            LabeledExprSyntax(label: "to", expression: ExprSyntax("entity\(raw: underlyingType.replacingOccurrences(of: "Entity", with: ""))"))
            LabeledExprSyntax(label: "named", expression: ExprSyntax("\"\(raw: identifierName)\""))
            LabeledExprSyntax(label: "maxCount", expression: ExprSyntax("\(raw: parsedVariable.isArray ? 0 : 1)"))
        }.as(ExprSyntax.self)
    } else {
        return nil
    }
}
