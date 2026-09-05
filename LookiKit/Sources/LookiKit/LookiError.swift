import Foundation

public enum LookiError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case api(code: Int, detail: String)
    case decoding(String)
    case network(String)

    /// Short French sentence suitable for a banner.
    public var userMessage: String {
        switch self {
        case .missingAPIKey: "Aucune clé API configurée."
        case .unauthorized: "Clé API refusée par Looki."
        case .rateLimited(let s):
            if let s { "Trop de requêtes. Nouvel essai dans \(Int(s.rounded())) s." } else { "Trop de requêtes. Réessaie dans un instant." }
        case .httpStatus(let code): "Le serveur Looki a répondu \(code)."
        case .api(_, let detail): "Looki : \(detail)"
        case .decoding: "Réponse inattendue du serveur Looki."
        case .network(let msg): "Réseau indisponible : \(msg)"
        }
    }
}
