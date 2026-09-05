import Foundation

/// Reads `{ "base_url": ..., "api_key": ... }` as written in ~/.config/looki/credentials.json.
struct CredentialsFile: Decodable {
    let baseUrl: String?
    let apiKey: String
}

enum CredentialsFileImporter {
    static func read(_ url: URL) throws -> CredentialsFile {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(CredentialsFile.self, from: Data(contentsOf: url))
    }
}
