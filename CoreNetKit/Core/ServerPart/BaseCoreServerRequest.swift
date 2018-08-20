//
//  Serverrequest.swift
//  Sample
//
//  Created by Alexander Kravchenkov on 06.07.17.
//  Copyright © 2017 Alexander Kravchenkov. All rights reserved.
//

import Foundation
import Alamofire

public class BaseCoreServerRequest: NSObject, CoreServerRequest {

    typealias PerformedRequest = (DataRequest) -> Void
    typealias Completion = (CoreServerResponse) -> Void

    public enum Method {
        case get
        case post
        case put
        case delete

        public var alamofire: Alamofire.HTTPMethod {
            switch self {
            case .get: return .get
            case .post: return .post
            case .put: return .put
            case .delete: return .delete
            }
        }
    }

    public enum Encoding {
        case defaultJson
        case defaultUrl
        case queryStringUrl

        public var alamofire: Alamofire.ParameterEncoding {
            switch self {
            case .defaultJson:
                return JSONEncoding.default
            case .defaultUrl:
                return URLEncoding.default
            case .queryStringUrl:
                return URLEncoding.queryString
            }
        }
    }

    /// Метод API
    public let path: String
    /// Результирующий URL запроса - включает baseUrl и path
    public let url: URL
    /// Метод (get, post, delete...)
    public let method: Method
    /// Токен для хедера
    public let tokenProvider: TokenProvider?
    /// Хидеры запроса
    public let headers: HTTPHeaders?
    /// Параметры запроса
    public var parameters: ServerRequestParameter
    /// serverIfFailReadFromCahce by default
    public var cachePolicy: CachePolicy

    public let customEncoding: Encoding?

    public let errorMapper: ErrorMapperAdapter?

    fileprivate var currentRequest: DataRequest? = nil
    fileprivate let cacheAdapter: CacheAdapter?

    /// Initlize reqest object.
    ///
    /// - Parameters:
    ///   - method: HTTP method (POST, PUT e.t.c)
    ///   - baseUrl: url path to root server resource
    ///   - relativeUrl: url path from root to services (to methods)
    ///   - tokenProvider: Object, that should provide access token to request
    ///   - headers: Its custom headers. **Doesn't needs to add default headers like MIME: Application/Json or Authorization:TOKEN. Only custom key-value pairs.**
    ///   - parameters: Request parametrs. They may be included in request body or in query string (form-url-encoding). It depends form `customEncoding`.
    ///   - customEncoding: Provide custom url encoding.
    ///   - errorMapper: Object that should implement mapping custom server errors.
    ///   - cacheAdapter: Object that should implement read/write to cache
    ///   - cachePolicy: Cache Policy **(soon moved out to Cache Adapter)**
    public init(method: Method, baseUrl: String, relativeUrl: String, tokenProvider: TokenProvider? = nil,
         headers: HTTPHeaders? = nil, parameters: ServerRequestParameter,
         customEncoding: Encoding? = nil, errorMapper: ErrorMapperAdapter? = nil,
         cacheAdapter: CacheAdapter? = nil, cachePolicy: CachePolicy = .serverOnly) {
        self.method = method
        self.tokenProvider = tokenProvider
        self.headers = headers
        self.path = relativeUrl
        self.url = (URL(string: baseUrl)?.appendingPathComponent(self.path))!
        self.parameters = parameters
        self.cachePolicy = cachePolicy
        self.customEncoding = customEncoding
        self.errorMapper = errorMapper
        self.cacheAdapter = cacheAdapter
        super.init()
    }

    public func perform(with completion: @escaping (CoreServerResponse) -> Void) {

        let requests = self.createRequestWithPolicy(with: completion)

        let performCreated: (RequestCompletion) -> Void = { result in
            switch result {
            case .succes(let request):
                requests.forEach({ $0(request) })
            case .failure(let error):
                completion(error)
            }
        }

        switch self.parameters {
        case .none:
            self.createNoneParamRequest(with: performCreated)
        case .simpleParams(let params):
            self.createSingleParamRequest(params, with: performCreated)
        case .multipartParams(let params):
            self.createMultipartParamRequest(params, with: performCreated)
        }
    }

    func createRequestWithPolicy(with completion: @escaping Completion) -> [PerformedRequest] {
        switch self.cachePolicy {
        case .cacheOnly:
            return [self.readFromCache(completion: completion)]
        case .serverOnly, .serverIfFailReadFromCahce:
            return [self.sendRequest(completion: completion)]
        case .firstCacheThenRefreshFromServer:
            let cacheRequest = self.readFromCache(completion: completion)
            let serverRequest = self.sendRequest(completion: completion)

            return [cacheRequest, serverRequest]
        }
    }

    /// Этот метод используется для отмены текущего запроса
    public func cancel() {
        currentRequest?.cancel()
    }

    // MARK: - Helps

    /// Возвращает хедеры, которые необходимы для данного запроса.
    func createHeaders() -> HTTPHeaders {
        var headers: HTTPHeaders = self.headers ?? [:]
        if let tokenProvider = self.tokenProvider, let tokenString = tokenProvider.getToken() {
            headers[tokenProvider.headerFieldName] = tokenString
        }
        return headers
    }
}

extension BaseCoreServerRequest {

    enum RequestCompletion {
        case succes(DataRequest)
        case failure(CoreServerResponse)
    }

    func createNoneParamRequest(with completion: @escaping (RequestCompletion) -> Void) {
        createSingleParamRequest(nil, with: completion)
    }

    func createSingleParamRequest(_ params: [String: Any]?, with completion: @escaping (RequestCompletion) -> Void) {

        let manager = ServerRequestsManager.shared.manager

        do {
            let request: URLRequest =  try self.createOriginalRequest(params: params)
            completion(.succes(manager.request(request)))
        } catch {
            let response = BaseCoreServerResponse(dataResponse: nil, dataResult: .failure(error), errorMapper: self.errorMapper)
            completion(.failure(response))
        }
    }

    func createMultipartParamRequest(_ params: [MultipartData], with completion: @escaping (RequestCompletion) -> Void) {

        let manager = ServerRequestsManager.shared.manager

        do {
            let request: URLRequest =  try self.createOriginalRequest(params: nil)
            manager.upload(multipartFormData: { (multipartFormData) in
                for data in params {
                    multipartFormData.append(data.data, withName: data.name, fileName: data.fileName, mimeType: data.mimeType)
                }
            }, with: request) { (encodingResult) in
                switch encodingResult {
                case let .success(request: uploadRequest, streamingFromDisk: _, streamFileURL: _):
                    completion(.succes(uploadRequest))
                case let .failure(error):
                    let response = BaseCoreServerResponse(dataResponse: nil, dataResult: .failure(error), errorMapper: self.errorMapper)
                    completion(.failure(response))
                }
            }
        } catch {
            let response = BaseCoreServerResponse(dataResponse: nil, dataResult: .failure(error), errorMapper: self.errorMapper)
            completion(.failure(response))
        }
    }

    func createOriginalRequest(params: [String: Any]?) throws -> URLRequest {
        let paramEncoding = {() -> ParameterEncoding in
            if let custom = self.customEncoding {
                return custom.alamofire
            }
            return self.method.alamofire == .get ? URLEncoding.default : JSONEncoding.default
        }()

        let headers = self.createHeaders()
        let originalRequest = try URLRequest(url: url, method: method.alamofire, headers: headers)
        var encodedURLRequest = try paramEncoding.encode(originalRequest, with: params)

        if let cacheAdapter = cacheAdapter,
            let configuredRequest = cacheAdapter.configure(encodedURLRequest) as? URLRequest {
            encodedURLRequest = configuredRequest
        }

        return encodedURLRequest
    }
}

// MARK: - Requests

extension BaseCoreServerRequest {

    func sendRequest(completion: @escaping Completion) -> PerformedRequest {
        let performRequest = { (request: DataRequest) -> Void in
            self.currentRequest = request
            request.response { afResponse in
                self.log(afResponse)
                var response: CoreServerResponse = BaseCoreServerResponse(dataResponse: afResponse, dataResult: .success(afResponse.data, false), errorMapper: self.errorMapper)

                // If response has flag NotModified in all cases we need to load cache
                var isNeedsToReadCache = response.isNotModified

                // If cache policy is serverIfFailReadFromCahce and request fails we need to:
                // 1. send failure completion
                // 2. try to load response from cache
                if self.cachePolicy == .serverIfFailReadFromCahce, case ResponseResult.failure = response.result {
                    isNeedsToReadCache = true
                    completion(response)
                }

                if isNeedsToReadCache,
                    let guardRequest = request.request, let guardedAdapter = self.cacheAdapter {
                    response = guardedAdapter.load(urlRequest: guardRequest, response: response)
                }

                if response.result.value != nil, let urlResponse = afResponse.response,
                    let data = afResponse.data, self.cachePolicy != .serverOnly,
                    let urlRequest = request.request, let guardedAdapter = self.cacheAdapter {
                    guardedAdapter.save(urlResponse: urlResponse, urlRequest: urlRequest, data: data)
                }

                completion(response)

            }
        }
        return performRequest
    }

    func readFromCache(completion: @escaping Completion) -> PerformedRequest {
        let performRequest = { (request: DataRequest) -> Void in
            guard let guardRequest = request.request, let guardedAdapter = self.cacheAdapter  else {
                return
            }
            completion(guardedAdapter.load(urlRequest: guardRequest, response: nil))
        }
        return performRequest
    }
}

// MARK: - Supported methods

extension BaseCoreServerRequest {
    func log(_ afResponse: DefaultDataResponse) {
        #if DEBUG
            let url: String = afResponse.request?.url?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let type: String = afResponse.request?.httpMethod ?? ""
            let headers: String = afResponse.request?.allHTTPHeaderFields?.description ?? ""
            let body = String(data: afResponse.request?.httpBody ?? Data(), encoding: String.Encoding.utf8) ?? ""
            let statusCode: String = "\(afResponse.response?.statusCode ?? 0)"
            let reponseHeaders: String = afResponse.response?.allHeaderFields.description ?? ""

            var responseBody: String = ""

            if let data = afResponse.data {
                responseBody = "\(String(data: data, encoding: .utf8) ?? "nil")"
            }
            NSLog("URL: \(url)")
            NSLog("REQUEST: \(type)")
            NSLog("HEADERS: \(headers)")
            NSLog("BODY: %@", body)
            NSLog("RESPONSE: \(statusCode)")
            NSLog("HEADERS: \(reponseHeaders)")
            NSLog("BODY: %@", responseBody)
            NSLog("TIMELINE: \(afResponse.timeline)")
        #else
        #endif
    }
}
