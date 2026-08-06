import UIKit

/// Satu petak foto di grid.
///
/// Kelas, bukan struct view — dan itulah intinya. `UICollectionView` MENDAUR
/// ULANG sel: berapa pun panjang perpustakaannya, yang pernah dibuat hanya
/// sebanyak yang muat di layar plus sedikit cadangan. Bandingkan dengan
/// `LazyVGrid`, yang membuat view baru untuk setiap sel yang masuk layar dan
/// tidak pernah membuangnya lagi.
final class PhotoGridCell: UICollectionViewCell {
    static let reuseID = "PhotoGridCell"

    private let imageView = UIImageView()
    private let badge = UIImageView()
    private let dimmer = UIView()
    /// Lama video, di pojok kanan bawah.
    ///
    /// Durasinya sendiri sudah menjadi penanda "ini video" — Photos pun tidak
    /// menambahkan ikon lagi di sampingnya.
    private let durationLabel = UILabel()

    /// Pemuatan yang sedang berjalan untuk sel INI.
    ///
    /// Dibatalkan di `prepareForReuse`: begitu selnya dipakai ulang untuk foto
    /// lain, hasil yang lama tidak ada gunanya lagi — dan menuliskannya justru
    /// membuat foto salah berkedip di posisi baru.
    private var loadTask: Task<Void, Never>?
    /// Kunci foto yang sedang dituju, untuk menolak hasil yang sudah basi.
    private var currentKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemFill
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)

        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        dimmer.frame = contentView.bounds
        dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmer.isHidden = true
        contentView.addSubview(dimmer)

        badge.image = UIImage(systemName: "checkmark.circle.fill")
        badge.tintColor = .white
        badge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
        ])

        durationLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        // Bayangan, bukan kotak berlatar: foto terang maupun gelap sama-sama
        // terbaca, tanpa menambah bidang berwarna di atas gambarnya.
        durationLabel.layer.shadowColor = UIColor.black.cgColor
        durationLabel.layer.shadowOpacity = 0.6
        durationLabel.layer.shadowRadius = 2
        durationLabel.layer.shadowOffset = .zero
        durationLabel.isHidden = true
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)
        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -3),
        ])

        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        currentKey = nil
        imageView.image = nil
        durationLabel.isHidden = true
        durationLabel.text = nil
        setSelectionState(showsSelection: false, isPicked: false)
    }

    func configure(with asset: AssetLite, loader: PhotoThumbnailLoader) {
        // Pemuatan lama DIBATALKAN dulu. Sel yang disusun ulang untuk aset yang
        // sama (mis. setelah terbang ke foto terbaru) akan menimpa `loadTask`
        // tanpa membatalkannya, dan karena `currentKey`-nya tidak berubah, task
        // lama tetap lolos penjagaan dan ikut menulis gambarnya.
        loadTask?.cancel()
        loadTask = nil

        let key = loader.cacheKey(for: asset.id)
        currentKey = key

        durationLabel.text = asset.durationText
        durationLabel.isHidden = asset.durationText == nil

        // Sudah ada di memori: dipasang seketika, tanpa `Task` sama sekali.
        if let cached = loader.cachedImage(for: asset.id) {
            imageView.image = cached
            return
        }

        // Selama terbang ke foto terbaru, thumbhash pun DILEWATI.
        //
        // Membongkarnya adalah decode DCT di main thread, dan cache thumbhash
        // hanya menampung ratusan entri — melintasi puluhan layar penuh dalam
        // setengah detik membuatnya berputar habis dan ratusan decode menumpuk
        // tepat di jalur yang sedang harus mulus. Latar sel sudah cukup mengisi.
        imageView.image = loader.isSuspended
            ? nil
            : ThumbHash.placeholder(for: asset.thumbhash)

        loadTask = Task { [weak self] in
            let image = await loader.image(for: asset.id)
            guard let self, !Task.isCancelled, self.currentKey == key, let image
            else { return }
            self.imageView.image = image
        }
    }

    /// Gambar yang SEDANG tergambar di petak ini.
    ///
    /// Transisi ke layar detail menerbangkan gambar ini, bukan mengambilnya lagi
    /// dari cache: apa yang dilihat pengguna saat menekan itulah yang harus ikut
    /// berangkat, termasuk kalau yang tampil masih placeholder thumbhash.
    var displayedImage: UIImage? { imageView.image }

    func setSelectionState(showsSelection: Bool, isPicked: Bool) {
        badge.isHidden = !(showsSelection && isPicked)
        dimmer.isHidden = !(showsSelection && isPicked)
        // Keduanya sama-sama di pojok kanan bawah; tanda centang yang menang.
        durationLabel.alpha = badge.isHidden ? 1 : 0
    }
}
