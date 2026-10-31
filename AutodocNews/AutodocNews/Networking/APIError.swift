import Foundation

nonisolated enum APIError: Error {
    case transport(URLError)
    case http(Int)
    case decoding
}

nonisolated enum UserFacingError {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Нет соединения с интернетом."
            case .timedOut:
                return "Сервер не ответил вовремя."
            default:
                break
            }
        }
        if case APIError.transport(let urlError) = error {
            return message(for: urlError)
        }
        if case APIError.http(let code) = error {
            return "Сервер вернул ошибку \(code)."
        }
        return "Не удалось загрузить данные."
    }
}
