//
//  CacheableContext.swift
//  CoreNetKit
//
//  Created by Александр Кравченков on 09.12.2017.
//  Copyright © 2017 Кравченков Александр. All rights reserved.
//

import Foundation

/// Divide success completion on cache completion and server completion
public protocol CacheableContextProtocol: ActionableContextProtocol {

    /// Called if coupled object completed operation succesfully
    ///
    /// - Parameter closure: callback
    @discardableResult
    func onCacheCompleted(_ closure: @escaping (ResultType) -> Void) -> Self
}
