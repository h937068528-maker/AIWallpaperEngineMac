import AppKit
import Combine
import Foundation
import Security

enum VolcengineConfigurationError: LocalizedError {
    case invalidKey
    case invalidModel
    case missingKey
    case invalidResponse
    case api(status: Int, message: String)
    case invalidImage
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            NSLocalizedString("ai_volcengine_invalid_key", comment: "")
        case .invalidModel:
            NSLocalizedString("ai_volcengine_invalid_model", comment: "")
        case .missingKey:
            NSLocalizedString("ai_volcengine_missing_key", comment: "")
        case .invalidResponse:
            NSLocalizedString("ai_volcengine_invalid_response", comment: "")
        case let .api(status, message):
            "\(NSLocalizedString("ai_volcengine_name", comment: "")) \(status): \(message)"
        case .invalidImage:
            NSLocalizedString("ai_volcengine_invalid_image", comment: "")
        case let .keychain(status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain error \(status)."
        }
    }
}

/// The raw Ark API key stays in the user's login Keychain and is never written
/// to UserDefaults, generation history, logs, or a model configuration file.
@MainActor
final class VolcengineAPIKeyStore: ObservableObject {
    static let shared = VolcengineAPIKeyStore()

    @Published private(set) var hasKey = false
    @Published private(set) var maskedKey = ""

    private let service = "com.aiwallpaperengine.mac.volcengine"
    private let account = "ark-image-generation-api-key"

    init() {
        refreshStatus()
    }

    func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            key.hasPrefix("ark-"),
            key.count >= 20,
            !key.contains(where: \.isWhitespace),
            let data = key.data(using: .utf8)
        else {
            throw VolcengineConfigurationError.invalidKey
        }

        let lookup = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insertion = lookup
            attributes.forEach { insertion[$0.key] = $0.value }
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw VolcengineConfigurationError.keychain(status)
            }
        } else if updateStatus != errSecSuccess {
            throw VolcengineConfigurationError.keychain(updateStatus)
        }
        refreshStatus()
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VolcengineConfigurationError.keychain(status)
        }
        refreshStatus()
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            throw VolcengineConfigurationError.keychain(status)
        }
        return key
    }

    func refreshStatus() {
        guard let key = try? read(), !key.isEmpty else {
            hasKey = false
            maskedKey = ""
            return
        }
        hasKey = true
        maskedKey = "\(key.prefix(4))••••••••\(key.suffix(4))"
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

@MainActor
final class VolcengineConfigurationStore: ObservableObject {
    static let shared = VolcengineConfigurationStore()

    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: modelKey) }
    }

    private let defaults: UserDefaults
    private let modelKey = "ai.volcengine.seedream.model.v1"
    static let defaultModelID = "doubao-seedream-4-0-250828"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        modelID = defaults.string(forKey: modelKey)
            ?? Self.defaultModelID
    }

    func saveModelID(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            value.count >= 3,
            !value.contains(where: \.isWhitespace)
        else {
            throw VolcengineConfigurationError.invalidModel
        }
        modelID = value
    }
}

@MainActor
final class VolcengineWallpaperProvider: AIWallpaperProvider {
    let id = "ai.volcengine.seedream"
    let displayName = "火山方舟 · Seedream"
    let isDemo = false

    private let keyStore: VolcengineAPIKeyStore
    private let configuration: VolcengineConfigurationStore
    private let session: URLSession
    private let endpoint = URL(
        string: "https://ark.cn-beijing.volces.com/api/v3/images/generations"
    )!

    init(
        keyStore: VolcengineAPIKeyStore = .shared,
        configuration: VolcengineConfigurationStore = .shared,
        session: URLSession = .shared
    ) {
        self.keyStore = keyStore
        self.configuration = configuration
        self.session = session
    }

    func generate(
        _ request: AIWallpaperGenerationRequest,
        destinationFolder: URL
    ) async throws -> AIWallpaperGenerationResult {
        guard let apiKey = try keyStore.read() else {
            throw VolcengineConfigurationError.missingKey
        }
        let model = configuration.modelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !model.isEmpty else {
            throw VolcengineConfigurationError.invalidModel
        }
        try Task.checkCancellation()

        let payload = VolcengineImagePayload(
            model: model,
            prompt: Self.wallpaperPrompt(request),
            size: "2048x1152",
            responseFormat: "url",
            watermark: false
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 240
        urlRequest.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (responseData, response) = try await session.data(for: urlRequest)
        try Self.validateHTTPResponse(data: responseData, response: response)
        let envelope = try JSONDecoder().decode(
            VolcengineImageEnvelope.self,
            from: responseData
        )
        guard let output = envelope.data.first else {
            throw VolcengineConfigurationError.invalidResponse
        }

        let imageData: Data
        if
            let encoded = output.base64JSON,
            let decoded = Data(base64Encoded: encoded)
        {
            imageData = decoded
        } else if let remoteURL = output.url {
            let (downloaded, downloadResponse) = try await session.data(
                from: remoteURL
            )
            try Self.validateHTTPResponse(
                data: downloaded,
                response: downloadResponse
            )
            imageData = downloaded
        } else {
            throw VolcengineConfigurationError.invalidResponse
        }

        guard
            imageData.count <= 80 * 1_024 * 1_024,
            let representation = NSBitmapImageRep(data: imageData),
            representation.pixelsWide > 0,
            representation.pixelsHigh > 0,
            let pngData = representation.representation(
                using: .png,
                properties: [:]
            )
        else {
            throw VolcengineConfigurationError.invalidImage
        }

        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )
        let id = UUID()
        let filename = "AI-Seedream-\(Self.timestamp())-\(id.uuidString.prefix(8)).png"
        let destinationURL = destinationFolder.appendingPathComponent(filename)
        try pngData.write(to: destinationURL, options: .atomic)

        return AIWallpaperGenerationResult(
            id: id,
            prompt: request.prompt.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            style: request.style,
            localPath: destinationURL.path,
            createdAt: Date()
        )
    }

    private static func validateHTTPResponse(
        data: Data,
        response: URLResponse
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw VolcengineConfigurationError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(
                VolcengineErrorEnvelope.self,
                from: data
            )
            throw VolcengineConfigurationError.api(
                status: response.statusCode,
                message: envelope?.error.message
                    ?? HTTPURLResponse.localizedString(
                        forStatusCode: response.statusCode
                    )
            )
        }
    }

    private static func wallpaperPrompt(
        _ request: AIWallpaperGenerationRequest
    ) -> String {
        """
        生成一张精致的 macOS 桌面壁纸。主题：\(request.prompt)
        视觉风格：\(request.style.rawValue)。
        构图适合桌面图标，保留平静的负空间；不要文字、标志、水印、
        用户界面元素或边框。宽屏 16:9，高细节，高品质。
        """
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

private struct VolcengineImagePayload: Encodable {
    let model: String
    let prompt: String
    let size: String
    let responseFormat: String
    let watermark: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case size
        case responseFormat = "response_format"
        case watermark
    }
}

private struct VolcengineImageEnvelope: Decodable {
    let data: [VolcengineImageOutput]
}

private struct VolcengineImageOutput: Decodable {
    let url: URL?
    let base64JSON: String?

    private enum CodingKeys: String, CodingKey {
        case url
        case base64JSON = "b64_json"
    }
}

private struct VolcengineErrorEnvelope: Decodable {
    let error: VolcengineErrorBody
}

private struct VolcengineErrorBody: Decodable {
    let message: String
}
