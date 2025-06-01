//
//  File.swift
//  
//
//  Created by Martin Lalev on 28/03/2024.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct PersistenceClientFactoryMacro: DeclarationMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let argument = node.argumentList.first else {
            return []
        }
        guard let member = argument.expression.as(MemberAccessExprSyntax.self) else {
            return []
        }
        guard let declReference = member.base?.as(DeclReferenceExprSyntax.self) else {
            return []
        }
        
        let protocolName = declReference.baseName.text
        let makeFunc = try FunctionDeclSyntax("func make() -> \(raw: protocolName)") {
            ExprSyntax(stringLiteral: "\(protocolName)Client(storageClient: self)")
        }
        return [DeclSyntax(makeFunc)]
    }
}
