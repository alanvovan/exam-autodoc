import Foundation

nonisolated enum NewsEndpoint {
    static let pageSize = 15
    private static let root = "https://webapi.autodoc.ru/api/news"

    static func page(_ page: Int, count: Int = pageSize) -> URL {
        url("\(root)/\(page)/\(count)")
    }

    static func item(path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return url("\(root)/item/\(trimmed)")
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Некорректный адрес API")
        }
        return url
    }
}
