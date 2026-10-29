import UIKit

final class NewsLayoutMetrics {
    weak var host: UICollectionView?
    var showsFooter = false
}

enum NewsLayout {
    static func make(metrics: NewsLayoutMetrics) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak metrics] _, environment in
            section(environment: environment, metrics: metrics)
        }
    }

    private static func section(
        environment: NSCollectionLayoutEnvironment,
        metrics: NewsLayoutMetrics?
    ) -> NSCollectionLayoutSection {
        let containerWidth = environment.container.effectiveContentSize.width
        let host = metrics?.host
        let prefersEven = host.map(DuoLayout.prefersEvenColumns(in:)) ?? false
        let columns = DuoLayout.columnCount(
            containerWidth: containerWidth,
            horizontal: environment.traitCollection.horizontalSizeClass,
            prefersEvenColumns: prefersEven
        )
        let hingeGap = hingeGap(host: host, columns: columns)

        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(280)
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(280)
            ),
            repeatingSubitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(hingeGap ?? 12)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

        if metrics?.showsFooter == true {
            let footer = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(52)
                ),
                elementKind: UICollectionView.elementKindSectionFooter,
                alignment: .bottom
            )
            section.boundarySupplementaryItems = [footer]
        }
        return section
    }

    /// На частично сложенном Duo увеличиваем зазор между двумя колонками до ширины сгиба.
    private static func hingeGap(host: UICollectionView?, columns: Int) -> CGFloat? {
        guard columns == 2, let host, let fold = DuoLayout.activeDivisionFrame(in: host) else { return nil }
        let bounds = host.bounds
        guard fold.minX > 80, fold.maxX < bounds.maxX - 80 else { return nil }
        return fold.width
    }
}
