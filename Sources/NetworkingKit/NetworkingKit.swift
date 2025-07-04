//
//  Networking.swift
//  NetworkingKit
//
//  Created by Nihal on 6/29/25.
//

import Foundation
import Combine
import Alamofire

public enum NetworkError: Error {
    case invalidURL
    case decodingError(String)
    case genericError(String)
    case invalidResponseCode(Int)
    
    /// Provides readable error messages for each network error case.
    public var errorMessageString: String {
        switch self {
        case .invalidURL:
            return "Invalid URL encountered. Can't proceed with the request"
        case .decodingError:
            return "Encountered an error while decoding server response."
        case .genericError(let message):
            return message
        case .invalidResponseCode(let code):
            return "Invalid response code. Expected 200, received \(code)"
        }
    }
}

public protocol NetworkingProtocol {
    
    /// Sends a GET request using Combine and returns a publisher with decoded response.
    ///
    /// - Parameters:
    ///   - urlString: The endpoint URL.
    ///   - headers: Request headers.
    ///   - query: Query parameters.
    ///   - modelType: Expected model to decode.
    /// - Returns: Publisher emitting decoded model or NetworkError.
    @available(iOS 13.0, macOS 10.15, *)
    func get<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError>
    
    /// Sends a POST request using Combine and returns a publisher with decoded response.
    ///
    /// - Parameters:
    ///   - urlString: The endpoint URL.
    ///   - params: Request body as dictionary.
    ///   - headers: Request headers.
    ///   - modelType: Model to decode.
    /// - Returns: Publisher emitting decoded model or NetworkError.
    @available(iOS 13.0, macOS 10.15, *)
    func post<T: Codable>(
        endPoint: String,
        params: [String: Any],
        headers: [String: String],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError>
    
    /// Sends a GET request using async/await and returns a decoded model.
    ///
    /// - Parameters:
    ///   - urlString: The endpoint URL.
    ///   - headers: Dictionary of headers to include in the request.
    ///   - query: Dictionary of query parameters.
    ///   - modelType: The expected Decodable model type.
    /// - Returns: Decoded object of type `T`.
    /// - Throws: `NetworkError` if URL is invalid, decoding fails, or response code is not 200.
    @available(iOS 13.0, macOS 12.0, *)
    func get<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) async throws -> T
    
    /// Sends a POST request using async/await and returns a decoded model.
    ///
    /// - Parameters:
    ///   - urlString: The endpoint URL in string format.
    ///   - headers: The headers to include in the request.
    ///   - params: The request body parameters in dictionary form.
    ///   - modelType: The expected Decodable model type for the response.
    /// - Returns: A decoded object of the given type `T`.
    /// - Throws: `NetworkError` if URL is invalid, decoding fails, or status code is incorrect.
    @available(iOS 13.0, macOS 12.0, *)
    func post<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        params: [String: Any],
        modelType: T.Type
    ) async throws -> T
    
    /// Sends a multipart request and returns upload result using Combine.
    ///
    /// - Parameters:
    ///   - method: HTTP method (default is .post).
    ///   - url: Upload endpoint.
    ///   - parameters: Form data including files.
    ///   - header: HTTP headers.
    ///   - progressCompleted: Upload progress closure.
    /// - Returns: Publisher with tuple of optional Data and URLResponse, or error.
    @available(iOS 13.0, macOS 10.15, *)
    func multipart(
        method: HTTPMethod,
        url: String,
        parameters: [String: Any],
        header: [String: String],
        progressCompleted: @escaping ((Progress) -> Void)) -> AnyPublisher<(Data?, URLResponse?), NetworkError>
}

@available(iOS 13.0, macOS 10.15, *)
public final class Networking: NetworkingProtocol {
    
    private let baseURL: String
    
    public init(baseURLString: String) {
        self.baseURL = baseURLString
    }
    
    public func get<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        var urlComponents = URLComponents(string: baseURL + (endPoint.hasPrefix("/") ? endPoint : "/\(endPoint)"))
        
        if !query.isEmpty {
            urlComponents?.queryItems = query.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }
        
        guard let url = urlComponents?.url else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw NetworkError.invalidResponseCode(httpResponse.statusCode)
                }
                return data
            }
            .decode(type: modelType, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .mapError {
                if let decoding = $0 as? DecodingError {
                    return NetworkError.decodingError((decoding as NSError).debugDescription)
                }
                return NetworkError.genericError($0.localizedDescription)
            }
            .eraseToAnyPublisher()
    }
    
    public func post<T: Codable>(
        endPoint: String,
        params: [String: Any],
        headers: [String: String],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        var urlComponents = URLComponents(string: baseURL + (endPoint.hasPrefix("/") ? endPoint : "/\(endPoint)"))
        
        guard let url = urlComponents?.url else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = params.toJsonObject()
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw NetworkError.invalidResponseCode(httpResponse.statusCode)
                }
                return data
            }
            .decode(type: modelType, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .mapError {
                if let decoding = $0 as? DecodingError {
                    return NetworkError.decodingError((decoding as NSError).debugDescription)
                }
                return NetworkError.genericError($0.localizedDescription)
            }
            .eraseToAnyPublisher()
    }
    
    @available(macOS 12.0, iOS 13.0, *)
    public func get<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) async throws -> T {
        
        var urlComponents = URLComponents(string: baseURL + (endPoint.hasPrefix("/") ? endPoint : "/\(endPoint)"))
        
        if !query.isEmpty {
            urlComponents?.queryItems = query.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }
        
        guard let url = urlComponents?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponseCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(modelType, from: data)
    }
    
    @available(macOS 12.0, iOS 13.0, *)
    public func post<T: Decodable>(
        endPoint: String,
        headers: [String: String],
        params: [String: Any],
        modelType: T.Type
    ) async throws -> T {
        
        var urlComponents = URLComponents(string: baseURL + (endPoint.hasPrefix("/") ? endPoint : "/\(endPoint)"))
        
        guard let url = urlComponents?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.toJsonObject()
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponseCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try JSONDecoder().decode(modelType, from: data)
    }
    
    @available(macOS 12.0, iOS 13.0, *)
    public func multipart(
        method: HTTPMethod = .post,
        url: String,
        parameters: [String: Any],
        header: [String: String] = [:],
        progressCompleted: @escaping ((Progress) -> Void) = { _ in }
    ) -> AnyPublisher<(Data?, URLResponse?), NetworkError> {
        
        var headers: HTTPHeaders = [:]
        for item in header {
            headers.add(name: item.key, value: item.value)
        }
        
        return Future<(Data?, URLResponse?), Error> { promise in
            let uploadRequest = AF.upload(
                multipartFormData: { multipartFormData in
                    for item in parameters {
                        if let postData = item.value as? PostData {
                            switch postData.type {
                            case .IMAGE:
                                multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpg")
                            case .VIDEO:
                                multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).mp4", mimeType: "video/mp4")
                            case .GIF:
                                multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).gif", mimeType: "image/gif")
                            case .PDF:
                                multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).pdf", mimeType: "application/pdf")
                            case .TEXT:
                                multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).txt", mimeType: "text/plain")
                            default: break
                            }
                        } else if let postDataArray = item.value as? [PostData] {
                            for postData in postDataArray {
                                switch postData.type {
                                case .IMAGE:
                                    multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).jpg", mimeType: "image/jpg")
                                case .VIDEO:
                                    multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).mp4", mimeType: "video/mp4")
                                case .GIF:
                                    multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).gif", mimeType: "image/gif")
                                case .PDF:
                                    multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).pdf", mimeType: "application/pdf")
                                case .TEXT:
                                    multipartFormData.append(postData.value, withName: "\(item.key)", fileName: "\(UUID().uuidString).txt", mimeType: "text/plain")
                                default: break
                                }
                            }
                        } else {
                            multipartFormData.append(("\(item.value)" as AnyObject).data(using: String.Encoding.utf8.rawValue)!, withName: item.key)
                            print("Key::\(item.key) -> Value::\(item.value)")
                        }
                    }
                },
                to: url,
                method: method,
                headers: headers
            )
            
            uploadRequest.response { response in
                switch response.result {
                case .success(let data):
                    promise(.success((data, response.response)))
                case .failure(let error):
                    if let afError = error.asAFError {
                        switch afError {
                        case .sessionTaskFailed(let urlError as URLError):
                            promise(.failure(NetworkError.genericError("Network issue: \(urlError.localizedDescription)")))
                        default:
                            promise(.failure(NetworkError.genericError("AFError: \(afError.localizedDescription)")))
                        }
                    } else {
                        promise(.failure(NetworkError.genericError(error.localizedDescription)))
                    }
                }
            }
            
            uploadRequest.uploadProgress { progress in
                print("Progress: \(progress.fractionCompleted * 100)%")
                progressCompleted(progress)
            }
        }
        .mapError { error in
            if let decodingError = error as? DecodingError {
                return .decodingError((decodingError as NSError).debugDescription)
            }
            return .genericError(error.localizedDescription)
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Dictionary Extensions

extension Dictionary {
    /// Converts dictionary to JSON Data.
    func toJsonObject() -> Data {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self, options: .prettyPrinted)
            return jsonData
        }
        catch {
            print(error.localizedDescription)
        }
        return Data()
    }
}

// MARK: - PostData & DOCUMENTTYPE

/// Represents supported file types for upload.
public enum DOCUMENTTYPE: String {
    case IMAGE, VIDEO, GIF, PDF, TEXT
}

/// Represents file data to be uploaded.
public class PostData: NSObject {
    public var value: Data!
    public var type: DOCUMENTTYPE!
    
    public init(value: Data, type: DOCUMENTTYPE) {
        super.init()
        self.value = value
        self.type = type
    }
}
