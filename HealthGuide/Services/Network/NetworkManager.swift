//
//  NetworkManager.swift
//  HealthGuide
//
//  Handles network requests to Supabase backend
//  Production-ready with error handling and retry logic
//

import Foundation

@available(iOS 18.0, *)
actor NetworkManager {
    
    // MARK: - Singleton
    static let shared = NetworkManager()
    
    // MARK: - HTTP Methods
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }
    
    // MARK: - Network Errors
    enum NetworkError: LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case serverError(Int)
        case networkError(Error)
        case unauthorized
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .noData:
                return "No data received"
            case .decodingError:
                return "Failed to decode response"
            case .serverError(let code):
                return "Server error: \(code)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .unauthorized:
                return "Unauthorized access"
            case .rateLimited:
                return "Too many requests"
            }
        }
    }
    
    // MARK: - Configuration
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    
    // MARK: - Initialization
    private init() {
        // Load configuration from Info.plist or environment
        // For now, using placeholder values - should be configured in production
        self.baseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://your-project.supabase.co"
        self.apiKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? "your-anon-key"
        
        // Configure URLSession with shorter timeouts for development
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10  // Reduced from 30 for faster failure
        config.timeoutIntervalForResource = 20  // Reduced from 60
        config.waitsForConnectivity = false  // Don't wait for connectivity
        config.httpAdditionalHeaders = [
            "apikey": apiKey,
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        self.session = URLSession(configuration: config)
        
        print("🌐 NetworkManager: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Make a network request to Supabase
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> T {
        // Construct URL
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add body if provided
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            // Make request
            let (data, response) = try await session.data(for: request)
            
            // Check response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        return try decoder.decode(T.self, from: data)
                    } catch {
                        print("❌ Decoding error: \(error)")
                        throw NetworkError.decodingError
                    }
                    
                case 401:
                    throw NetworkError.unauthorized
                    
                case 429:
                    // Rate limited - retry with exponential backoff
                    if retryCount < maxRetries {
                        let delay = retryDelay * pow(2, Double(retryCount))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        return try await self.request(
                            endpoint: endpoint,
                            method: method,
                            body: body,
                            headers: headers,
                            retryCount: retryCount + 1
                        )
                    }
                    throw NetworkError.rateLimited
                    
                default:
                    throw NetworkError.serverError(httpResponse.statusCode)
                }
            }
            
            throw NetworkError.noData
            
        } catch {
            // Retry on network errors
            if retryCount < maxRetries {
                let delay = retryDelay * pow(2, Double(retryCount))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await self.request(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    headers: headers,
                    retryCount: retryCount + 1
                )
            }
            
            throw NetworkError.networkError(error)
        }
    }
    
    /// Make a network request that returns raw dictionary
    func request(
        endpoint: String,
        method: HTTPMethod,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> [String: Any] {
        // Construct URL
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        
        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Add body if provided
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            // Make request
            let (data, response) = try await session.data(for: request)
            
            // Check response
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    // Success - decode response
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NetworkError.decodingError
                    }
                    return json
                    
                case 401:
                    throw NetworkError.unauthorized
                    
                case 429:
                    // Rate limited - retry with exponential backoff
                    if retryCount < maxRetries {
                        let delay = retryDelay * pow(2, Double(retryCount))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        return try await self.request(
                            endpoint: endpoint,
                            method: method,
                            body: body,
                            headers: headers,
                            retryCount: retryCount + 1
                        )
                    }
                    throw NetworkError.rateLimited
                    
                default:
                    throw NetworkError.serverError(httpResponse.statusCode)
                }
            }
            
            throw NetworkError.noData
            
        } catch {
            // Retry on network errors
            if retryCount < maxRetries {
                let delay = retryDelay * pow(2, Double(retryCount))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await self.request(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    headers: headers,
                    retryCount: retryCount + 1
                )
            }
            
            throw NetworkError.networkError(error)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// GET request
    func get<T: Decodable>(endpoint: String, headers: [String: String]? = nil) async throws -> T {
        return try await request(endpoint: endpoint, method: .get, headers: headers)
    }
    
    /// POST request
    func post<T: Decodable>(endpoint: String, body: [String: Any]? = nil, headers: [String: String]? = nil) async throws -> T {
        return try await request(endpoint: endpoint, method: .post, body: body, headers: headers)
    }
    
    /// PUT request
    func put<T: Decodable>(endpoint: String, body: [String: Any]? = nil, headers: [String: String]? = nil) async throws -> T {
        return try await request(endpoint: endpoint, method: .put, body: body, headers: headers)
    }
    
    /// DELETE request
    func delete(endpoint: String, headers: [String: String]? = nil) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, method: .delete, headers: headers)
    }
}

// MARK: - Empty Response for DELETE requests
struct EmptyResponse: Decodable {}