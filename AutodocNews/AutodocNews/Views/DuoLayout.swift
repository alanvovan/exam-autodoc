import UIKit

enum DuoLayout {
    static func columnCount(
        containerWidth: CGFloat,
        horizontal: UIUserInterfaceSizeClass,
        prefersEvenColumns: Bool
    ) -> Int {
        let base: Int
        if horizontal == .compact {
            base = 1
        } else if containerWidth >= 1000 {
            base = 3
        } else {
            base = 2
        }
        // Внутренний экран Duo делится сгибом. Нечётное число колонок кладёт карточку на шарнир.
        guard prefersEvenColumns, base == 3 else { return base }
        return 2
    }

    static func prefersEvenColumns(in view: UIView) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return !view.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    /// Кадр активного сгиба в координатах view. На раскрытом Duo ширина нулевая — его нет.
    static func activeDivisionFrame(in view: UIView) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let region = view.reservedRegions(kind: .division).first(where: { $0.isActive && $0.frame.width > 1 }) else {
            return nil
        }
        return region.frame
    }

    /// Уводит контент с шарнира на более широкую сторону. При равных половинах — на замыкающую.
    static func hingeContentInsets(fold: CGRect, bounds: CGRect) -> UIEdgeInsets {
        guard fold.intersects(bounds), fold.width > 1 else { return .zero }
        let left = fold.minX - bounds.minX
        let right = bounds.maxX - fold.maxX
        guard left > 24, right > 24 else { return .zero }
        if left > right + 40 {
            return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: bounds.maxX - fold.minX)
        }
        return UIEdgeInsets(top: 0, left: fold.maxX - bounds.minX, bottom: 0, right: 0)
    }
}

@MainActor
enum NewsDateFormatting {
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static func caption(category: String, date: Date) -> String {
        "\(category) · \(display.string(from: date))"
    }
}
