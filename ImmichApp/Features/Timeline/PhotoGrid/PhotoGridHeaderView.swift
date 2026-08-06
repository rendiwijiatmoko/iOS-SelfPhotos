import UIKit

/// Judul bulan yang menempel di tepi atas saat digulir.
final class PhotoGridHeaderView: UICollectionReusableView {
    static let reuseID = "PhotoGridHeaderView"

    private let label = UILabel()
    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)

        background.frame = bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(background)

        label.font = .preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    func configure(title: String) {
        label.text = title
    }
}
