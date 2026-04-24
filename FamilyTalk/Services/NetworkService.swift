//
//  NetworkService.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, body: String?)
    case decodingError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Неверный URL"
        case .invalidResponse: return "Неверный ответ сервера"
        case .unauthorized: return "Требуется авторизация"
        case .httpError(let code, let body):
            return "Ошибка HTTP \(code)\(body.map { ": \($0)" } ?? "")"
        case .decodingError(let e): return "Ошибка декодирования: \(e.localizedDescription)"
        case .unknown(let e): return e.localizedDescription
        }
    }
}

extension Notification.Name {
    static let networkUnauthorized = Notification.Name("networkUnauthorized")
}

final class NetworkService {
    static let shared = NetworkService()

    var baseURL = "http://localhost:3000"
    private(set) var accessToken: String?

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        // Handle ISO 8601 with and without fractional seconds
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let string = try container.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: string) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(string)"
            )
        }
    }

    func setAccessToken(_ token: String) { accessToken = token }
    func clearAccessToken() { accessToken = nil }

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        if let queryItems { components.queryItems = queryItems }
        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if http.statusCode == 401 {
            NotificationCenter.default.post(name: .networkUnauthorized, object: nil)
            throw NetworkError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.httpError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}
