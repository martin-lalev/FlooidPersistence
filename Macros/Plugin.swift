//
//  MockClient.swift
//  DandaniaMockServer
//
//  Created by Martin Lalev on 4.07.20.
//  Copyright © 2020 Martin Lalev. All rights reserved.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PersistenceClientServiceMacro.self,
        PersistenceClientModelMacro.self,
        PersistenceClientModelMemberMacro.self,
        PersistenceClientMemberMacro.self,
        PersistenceClientFactoryMacro.self,
    ]
}
