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
    
    @available(iOS 13.0, macOS 12.0, *)
    func get<T: Decodable>(
        urlString: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) async throws -> T
    
    @available(iOS 13.0, macOS 12.0, *)
    func post<T: Decodable>(
        urlString: String,
        headers: [String: String],
        params: [String: Any],
        modelType: T.Type
    ) async throws -> T
    
    @available(iOS 13.0, macOS 10.15, *)
    func getPublisher<T: Decodable>(
        urlString: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError>
    
    @available(iOS 13.0, macOS 10.15, *)
    func postPublisher<T: Codable>(
        urlString: String,
        params: [String: Any],
        headers: [String: String],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError>
    
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
    
    public init() {}
    
    // MARK: - Combine Publisher (GET)
    public func getPublisher<T: Decodable>(
        urlString: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        var urlStringWithQuery = urlString + query.toQuery()
        urlStringWithQuery = urlStringWithQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: urlStringWithQuery) else {
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode), httpResponse.statusCode != 400 {
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

    // MARK: - Combine Publisher (POST)
    public func postPublisher<T: Codable>(
        urlString: String,
        params: [String: Any],
        headers: [String: String],
        modelType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        guard let url = URL(string: urlString) else {
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
                   !(200...299).contains(httpResponse.statusCode), httpResponse.statusCode != 400 {
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

    // MARK: - Async/Await (GET)
    @available(macOS 12.0, iOS 13.0, *)
    public func get<T: Decodable>(
        urlString: String,
        headers: [String: String],
        query: [String: Any],
        modelType: T.Type
    ) async throws -> T {
        
        var urlStringWithQuery = urlString + query.toQuery()
        urlStringWithQuery = urlStringWithQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: urlStringWithQuery) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 400 else {
            throw NetworkError.invalidResponseCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(modelType, from: data)
    }

    // MARK: - Async/Await (POST)
    @available(macOS 12.0, iOS 13.0, *)
    public func post<T: Decodable>(
        urlString: String,
        headers: [String: String],
        params: [String: Any],
        modelType: T.Type
    ) async throws -> T {
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.toJsonObject()

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 400 else {
            throw NetworkError.invalidResponseCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(modelType, from: data)
    }
    
    // MARK: - Multipart (POST)
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
                    promise(.failure(NetworkError.genericError(error.localizedDescription)))
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
    func percentEncoded() -> Data? {
        return map { key, value in
            let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return escapedKey + "=" + escapedValue
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
    
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
    
    func toQuery() -> String {
        let queryDic = self
        var queryString = "?"
        for item in queryDic {
            queryString += item.key as! String
            queryString += "="
            queryString += "\(item.value)"
            queryString += "&"
        }
        queryString = String(queryString.dropLast())
        return queryString
    }
}

// MARK: - PostData & DOCUMENTTYPE

public enum DOCUMENTTYPE: String {
    case IMAGE, VIDEO, GIF, PDF, TEXT
}

public class PostData: NSObject {
    public var value: Data!
    public var type: DOCUMENTTYPE!

    public init(value: Data, type: DOCUMENTTYPE) {
        super.init()
        self.value = value
        self.type = type
    }
}
