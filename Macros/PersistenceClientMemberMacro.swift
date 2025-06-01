//
//  File.swift
//  
//
//  Created by Martin Lalev on 28/03/2024.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct PersistenceClientMemberMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return []
    }
}
