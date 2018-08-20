//
//  OrderServiceAsyncIterator.swift
//  GoLamaGo
//
//  Created by Alexander Kravchenkov on 13.09.17.
//  Copyright © 2017 Surf. All rights reserved.
//

import Foundation
import CoreEvents

/// Base context that implement iteratable logic for any iteratable request
public class IteratableContext<ResultModel: Countable>: ActionableContext<ResultModel>, ServiceAsyncIterator {

    // MARK: - Typealiases

    public typealias ResultType = ResultModel
    public typealias Model = ResultModel
    public typealias CompletedClosure = (ResultType) -> Void
    public typealias ErrorClosure = (Error) -> Void

    // MARK: - Private fileds

    fileprivate let startIndex: Int
    fileprivate var currentIndex: Int
    fileprivate let itemsOnPage: Int
    fileprivate let paginableContext: PagingRequestContext<ResultModel>
    private var completedEvents: Event<ResultType>
    private var errorEvents: Event<Error>

    // MARK: - Public properties

    public var canMoveNext: Bool

    // MARK: - Initializers

    public required init(startIndex: Int, itemsOnPage: Int, context: PagingRequestContext<ResultModel>) {
        self.startIndex = startIndex
        self.currentIndex = startIndex
        self.itemsOnPage = itemsOnPage
        self.canMoveNext = true
        self.paginableContext = context
        self.completedEvents = Event<ResultType>()
        self.errorEvents = Event<Error>()
        super.init()
        self.subscribe()
    }

    // MARK: - Iteratables

    public func moveNext() {
        self.paginableContext.pagin(startIndex: self.currentIndex, itemsOnPage: self.itemsOnPage)
    }

    public func reset(to index: Int? = nil) {
        guard let guardedIndex = index else {
            self.currentIndex = self.startIndex
            return
        }
        self.currentIndex = guardedIndex
    }

    // MARK: - Actionable context

    @discardableResult
    public override func onCompleted(_ closure: @escaping CompletedClosure) -> Self {
        self.completedEvents += closure
        return self
    }

    @discardableResult
    public override func onError(_ closure: @escaping ErrorClosure) -> Self {
        self.errorEvents += closure
        return self
    }
}

private extension IteratableContext {

    func subscribe() {
        self.paginableContext.onCompleted { [weak self] result in

            guard let `self` = self else {
                return
            }

            self.canMoveNext = !result.itemsIsEmpty
            self.currentIndex += result.itemsCount
            self.completedEvents.invoke(with: result)
        }.onError { [weak self] result in

            guard let `self` = self else {
                return
            }

            self.canMoveNext = false
            self.errorEvents.invoke(with: result)
        }
    }
}
