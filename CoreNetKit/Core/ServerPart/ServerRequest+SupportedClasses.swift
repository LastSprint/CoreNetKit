//
//  ServerRequest+SupportedClasses.swift
//  Sample
//
//  Created by Alexander Kravchenkov on 07.07.17.
//  Copyright © 2017 Alexander Kravchenkov. All rights reserved.
//

import Foundation
import Alamofire

public enum ServerRequestParameter {
    case none
    case simpleParams([String: Any]?)
    case multipartParams([MultipartData])
}

public class ServerRequestsManager {

    static let shared = ServerRequestsManager()

    let manager: SessionManager

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 60 * 3
        configuration.timeoutIntervalForRequest = 60 * 3
        configuration.requestCachePolicy = .reloadIgnoringCacheData
        configuration.urlCache = nil
        self.manager = Alamofire.SessionManager(configuration: configuration)
    }
}

public enum CachePolicy {
    case serverOnly
    case cacheOnly
    case firstCacheThenRefreshFromServer
    case serverIfFailReadFromCahce
}
