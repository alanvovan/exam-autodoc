import Foundation

nonisolated struct NewsItem: Decodable, Hashable, Sendable {
    let id: Int
    let title: String
    let description: String
    let publishedDate: Date
    let url: String
    let fullUrl: String
    let titleImageURL: URL?
    let categoryType: String

    private enum CodingKeys: String, CodingKey {
        case id, title, description, publishedDate, url, fullUrl, categoryType
        case titleImageUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        publishedDate = try container.decode(Date.self, forKey: .publishedDate)
        url = try container.decode(String.self, forKey: .url)
        fullUrl = try container.decode(String.self, forKey: .fullUrl)
        categoryType = try container.decode(String.self, forKey: .categoryType)
        let rawImage = try container.decodeIfPresent(String.self, forKey: .titleImageUrl)
        if let rawImage, !rawImage.isEmpty, let parsed = URL(string: rawImage) {
            titleImageURL = parsed
        } else {
            titleImageURL = nil
        }
    }
}

nonisolated struct NewsPage: Decodable, Sendable {
    let news: [NewsItem]
    let totalCount: Int
}

nonisolated struct NewsDetail: Decodable, Sendable {
    let item: NewsItem
    let text: String

    private enum CodingKeys: String, CodingKey {
        case text
    }

    init(from decoder: Decoder) throws {
        item = try NewsItem(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}
