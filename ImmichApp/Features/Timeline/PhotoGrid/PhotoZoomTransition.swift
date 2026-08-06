import UIKit

/// Penanda scroll view yang memegang foto di layar detail.
///
/// Transisi perlu kotak AKHIR fotonya, dan menebaknya dari ukuran layar tidak
/// bisa: aturan tingginya hidup di `PhotoPagerCell` dan berubah mengikuti panel
/// info. Ditandai begini, kotaknya dibaca dari yang benar-benar tergambar.
let photoZoomContentIdentifier = "photo.zoom.content"

/// Foto yang sedang dilihat di sebuah hierarki layar detail.
///
/// Pager menyisakan beberapa sel hidup sekaligus, jadi yang dipilih adalah yang
/// paling dekat dengan tengah layar.
@MainActor
func photoZoomContentView(in root: UIView) -> UIView? {
    var best: UIView?
    var bestDistance = CGFloat.greatestFiniteMagnitude

    func walk(_ view: UIView) {
        if view.accessibilityIdentifier == photoZoomContentIdentifier,
           let content = view.subviews.first {
            let center = view.convert(CGPoint(x: view.bounds.midX, y: 0), to: root)
            let distance = abs(center.x - root.bounds.midX)
            if distance < bestDistance {
                bestDistance = distance
                best = content
            }
        }
        view.subviews.forEach(walk)
    }
    walk(root)

    return best
}

/// Apa yang dibutuhkan animator dari sisi grid.
@MainActor
protocol PhotoZoomTransitionSource: AnyObject {
    /// Gambar dan kotak sel sebuah foto, dalam koordinat window. Grid ikut
    /// digulir kalau selnya sedang di luar layar.
    func zoomSource(for id: String) -> (image: UIImage?, frame: CGRect)?
    /// Menyembunyikan sel selama fotonya "terbang", supaya tidak terlihat dua
    /// kali di tempat yang sama.
    func setZoomSourceHidden(_ hidden: Bool, for id: String)
}

/// Transisi foto ala Photos: petak di grid tumbuh menjadi foto layar penuh.
///
/// `.zoom(sourceID:in:)` milik SwiftUI tidak bisa melakukan ini, dan bukan karena
/// sisi UIKit-nya. Transisi itu menskalakan SELURUH view tujuan dari kotak
/// sumbernya — sementara sel grid berisi foto ter-crop persegi (`scaleAspectFill`)
/// dan layar detail berisi foto utuh di tengah latar hitam (`scaleAspectFit`).
/// Penskalaan murni tidak akan pernah membuat kedua bingkai itu berhimpit.
///
/// Di sini satu `UIImageView` melayang ber-`scaleAspectFill` diterbangkan dari
/// kotak sel ke kotak foto. Karena kotak tujuan punya rasio yang sama dengan
/// fotonya, `fill` dan `fit` bertemu tepat di ujung animasi — crop-nya membuka
/// sendiri sepanjang jalan, tanpa langkah terpisah yang perlu dianimasikan.
@MainActor
final class PhotoZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool
    private weak var source: (any PhotoZoomTransitionSource)?
    /// Foto yang sedang jadi pokok transisi; berubah kalau pengguna mengusap ke
    /// foto lain sebelum menutup.
    private let assetID: () -> String
    /// Rasio foto, untuk menghitung kotak tujuan kalau layar detail belum sempat
    /// menata dirinya.
    private let aspectRatio: () -> CGFloat

    init(
        isPresenting: Bool,
        source: any PhotoZoomTransitionSource,
        assetID: @escaping () -> String,
        aspectRatio: @escaping () -> CGFloat
    ) {
        self.isPresenting = isPresenting
        self.source = source
        self.assetID = assetID
        self.aspectRatio = aspectRatio
    }

    func transitionDuration(
        using transitionContext: (any UIViewControllerContextTransitioning)?
    ) -> TimeInterval {
        isPresenting ? 0.42 : 0.34
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        if isPresenting {
            present(using: context)
        } else {
            dismiss(using: context)
        }
    }

    // MARK: - Membuka

    private func present(using context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        guard let detail = context.viewController(forKey: .to), let detailView = detail.view else {
            context.completeTransition(false)
            return
        }

        detailView.frame = context.finalFrame(for: detail)
        detailView.alpha = 0
        container.addSubview(detailView)

        // Layout dipaksa selesai lebih dulu supaya kotak akhir fotonya bisa
        // dibaca, bukan ditebak.
        detailView.setNeedsLayout()
        detailView.layoutIfNeeded()

        let duration = transitionDuration(using: context)

        // Latar dan chrome-nya memudar masuk lebih cepat daripada fotonya
        // terbang. Ini SATU animasi tersendiri, bukan bagian dari completion:
        // apa pun yang terjadi pada sisa transisinya, layar detail dijamin
        // berakhir terlihat. Itu pelajaran dari layar hitam kemarin.
        UIView.animate(withDuration: duration * 0.45) { detailView.alpha = 1 }

        let id = assetID()
        guard let start = source?.zoomSource(for: id), let image = start.image else {
            context.completeTransition(!context.transitionWasCancelled)
            return
        }

        let destination = measuredPhoto(in: detailView)
        let target = destination.map { $0.convert($0.bounds, to: container) }
            ?? aspectFitRect(ratio: aspectRatio(), inside: container.bounds)

        let flying = makeFlyingView(
            image: image,
            frame: container.convert(start.frame, from: nil),
            cornerRadius: 0)
        container.addSubview(flying)

        // Keduanya disembunyikan selama penerbangan: sel di grid dan foto di
        // layar detail. Yang terlihat cuma satu gambar yang berpindah.
        destination?.isHidden = true
        source?.setZoomSourceHidden(true, for: id)

        animateCornerRadius(flying, to: destination?.layer.cornerRadius ?? 0, duration: duration)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0
        ) {
            flying.frame = target
        } completion: { _ in
            destination?.isHidden = false
            flying.removeFromSuperview()
            self.source?.setZoomSourceHidden(false, for: id)
            context.completeTransition(!context.transitionWasCancelled)
        }
    }

    // MARK: - Menutup

    private func dismiss(using context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        guard let detail = context.viewController(forKey: .from), let detailView = detail.view else {
            context.completeTransition(false)
            return
        }

        let duration = transitionDuration(using: context)
        let id = assetID()

        // Grid digulir lebih dulu supaya sel tujuannya benar-benar ada — persis
        // seperti Photos yang menggeser gridnya di balik layar detail.
        let destination = source?.zoomSource(for: id)
        let photo = measuredPhoto(in: detailView)
        let image = (photo as? UIImageView)?.image ?? destination?.image

        guard let endFrame = destination?.frame, let image, let photo else {
            UIView.animate(withDuration: duration) {
                detailView.alpha = 0
            } completion: { _ in
                detailView.alpha = 1
                context.completeTransition(!context.transitionWasCancelled)
            }
            return
        }

        let flying = makeFlyingView(
            image: image,
            frame: photo.convert(photo.bounds, to: container),
            cornerRadius: photo.layer.cornerRadius)
        container.addSubview(flying)

        photo.isHidden = true
        source?.setZoomSourceHidden(true, for: id)

        // Layar detailnya lenyap lebih cepat daripada fotonya terbang, jadi yang
        // terlihat menyusut hanya fotonya, bukan seluruh layar.
        UIView.animate(withDuration: duration * 0.5) { detailView.alpha = 0 }
        animateCornerRadius(flying, to: 0, duration: duration)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0
        ) {
            flying.frame = container.convert(endFrame, from: nil)
        } completion: { _ in
            photo.isHidden = false
            detailView.alpha = 1
            flying.removeFromSuperview()
            self.source?.setZoomSourceHidden(false, for: id)
            context.completeTransition(!context.transitionWasCancelled)
        }
    }

    // MARK: - Perkakas

    /// Foto tujuan, HANYA kalau ukurannya sudah nyata.
    ///
    /// View yang ada tapi belum terukur mengembalikan kotak nol di pojok kiri
    /// atas, dan menerbangkan gambar ke sana persis seperti melihatnya lenyap ke
    /// sudut layar. Lebih baik jatuh ke perkiraan aspect-fit daripada memakai
    /// angka yang jelas belum jadi.
    private func measuredPhoto(in detailView: UIView) -> UIView? {
        guard let photo = photoZoomContentView(in: detailView),
              photo.bounds.width > 1, photo.bounds.height > 1
        else { return nil }
        return photo
    }

    private func makeFlyingView(
        image: UIImage, frame: CGRect, cornerRadius: CGFloat
    ) -> UIImageView {
        let view = UIImageView(image: image)
        // `scaleAspectFill` + clip inilah yang membuat crop-nya membuka sendiri:
        // di kotak persegi sel gambarnya terpotong, di kotak tujuan yang serasio
        // ia kebetulan pas.
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.frame = frame
        view.layer.cornerRadius = cornerRadius
        return view
    }

    private func aspectFitRect(ratio: CGFloat, inside bounds: CGRect) -> CGRect {
        let ratio = max(ratio, 0.05)
        let scale = min(bounds.width / ratio, bounds.height)
        let size = CGSize(width: ratio * scale, height: scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height)
    }

    private func animateCornerRadius(_ view: UIView, to radius: CGFloat, duration: TimeInterval) {
        guard view.layer.cornerRadius != radius else { return }
        let animation = CABasicAnimation(keyPath: "cornerRadius")
        animation.fromValue = view.layer.cornerRadius
        animation.toValue = radius
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(animation, forKey: "cornerRadius")
        view.layer.cornerRadius = radius
    }
}

/// Menyambungkan animator ke presentasi modal layar detail.
@MainActor
final class PhotoZoomTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    private weak var source: (any PhotoZoomTransitionSource)?
    /// Diperbarui saat pengguna mengusap ke foto lain, supaya menutupnya mengecil
    /// ke sel yang benar — bukan ke foto yang pertama dibuka.
    var assetID: String
    var aspectRatio: CGFloat

    init(source: any PhotoZoomTransitionSource, assetID: String, aspectRatio: CGFloat) {
        self.source = source
        self.assetID = assetID
        self.aspectRatio = aspectRatio
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source presentingSource: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        animator(isPresenting: true)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        animator(isPresenting: false)
    }

    private func animator(isPresenting: Bool) -> PhotoZoomAnimator? {
        guard let source else { return nil }
        return PhotoZoomAnimator(
            isPresenting: isPresenting,
            source: source,
            assetID: { [weak self] in self?.assetID ?? "" },
            aspectRatio: { [weak self] in self?.aspectRatio ?? 1 })
    }
}

// MARK: - Tarik untuk menutup

/// Boleh tidaknya layar detail ditutup dengan tarikan, ditanyakan langsung ke
/// halaman foto yang sedang tampil.
@MainActor
func photoZoomDismissAllowed(in root: UIView) -> Bool {
    var view: UIView? = photoZoomContentView(in: root)
    while let current = view {
        if let page = current as? PhotoPagerCell { return page.allowsInteractiveDismiss }
        view = current.superview
    }
    return false
}

/// Tarik foto ke bawah untuk menutup, seperti di Photos.
///
/// Ini TIDAK memakai `UIPercentDrivenInteractiveTransition`. Yang itu menggeser
/// maju-mundur satu animasi yang sudah jadi — cocok untuk mendorong halaman,
/// salah untuk gestur ini: fotonya harus benar-benar mengikuti jari, mengecil
/// sambil turun, dan boleh dilepas ke mana saja. Jadi fotonya diangkat ke window
/// sebagai satu `UIImageView` yang digerakkan langsung, dan penutupannya baru
/// dijalankan setelah jari lepas.
///
/// Untungnya keadaan akhir gestur ini sama persis dengan keadaan awal animator
/// penutup: satu gambar melayang yang tinggal diterbangkan ke sel asalnya.
@MainActor
final class PhotoZoomDismissGesture: NSObject, UIGestureRecognizerDelegate {
    private weak var presented: UIViewController?
    private weak var source: (any PhotoZoomTransitionSource)?
    private let assetID: () -> String

    /// Gambar yang sedang digerakkan jari, hidup di window supaya tidak ikut
    /// memudar bersama latar layar detail.
    private var flying: UIImageView?
    /// Foto asli yang disembunyikan selama gestur.
    private weak var hiddenPhoto: UIView?
    private var startFrame: CGRect = .zero

    init(presented: UIViewController, source: any PhotoZoomTransitionSource, assetID: @escaping () -> String) {
        self.presented = presented
        self.source = source
        self.assetID = assetID
        super.init()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        presented.view.addGestureRecognizer(pan)
    }

    /// Jarak tarikan yang dianggap penuh — sebagian tinggi layar, bukan
    /// seluruhnya, supaya menutup tidak menuntut tarikan sampai ke dasar.
    private func dismissDistance(_ root: UIView) -> CGFloat {
        max(1, root.bounds.height * 0.45)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let presented, let root = presented.view else { return }

        switch pan.state {
        case .began:
            begin(in: root)

        case .changed:
            guard let flying else { return }
            let translation = pan.translation(in: root)
            let progress = min(max(translation.y / dismissDistance(root), 0), 1)
            // Mengecil sambil turun, tapi tidak sampai hilang: 0,7 kali masih
            // cukup besar untuk terbaca sebagai foto yang sama.
            let scale = 1 - progress * 0.3

            flying.center = CGPoint(
                x: startFrame.midX + translation.x,
                y: startFrame.midY + translation.y)
            flying.transform = CGAffineTransform(scaleX: scale, y: scale)
            // Latar dan chrome memudar memperlihatkan grid di belakangnya —
            // fotonya tidak ikut karena ia sudah berada di window.
            root.alpha = 1 - progress * 0.95

        case .ended:
            let translation = pan.translation(in: root)
            let progress = min(max(translation.y / dismissDistance(root), 0), 1)
            let velocity = pan.velocity(in: root).y
            // Lemparan cepat menutup walau jaraknya belum jauh — itu yang
            // membedakan gestur yang terasa hidup dari yang terasa kaku.
            if progress > 0.25 || velocity > 900 {
                commit(in: root)
            } else {
                cancel(in: root)
            }

        case .cancelled, .failed:
            cancel(in: root)

        default:
            break
        }
    }

    // MARK: Tahapan

    private func begin(in root: UIView) {
        guard flying == nil,
              let window = root.window,
              let photo = photoZoomContentView(in: root),
              let image = (photo as? UIImageView)?.image
        else { return }

        startFrame = photo.convert(photo.bounds, to: nil)

        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.frame = startFrame
        view.layer.cornerRadius = photo.layer.cornerRadius
        window.addSubview(view)

        photo.isHidden = true
        hiddenPhoto = photo
        flying = view
    }

    private func commit(in root: UIView) {
        guard let flying else { return }
        let id = assetID()

        // Grid ikut digulir kalau sel tujuannya di luar layar; kalau tidak
        // ketemu, fotonya cukup memudar di tempat.
        guard let destination = source?.zoomSource(for: id) else {
            UIView.animate(withDuration: 0.2) {
                flying.alpha = 0
                root.alpha = 0
            } completion: { _ in self.finish() }
            return
        }

        source?.setZoomSourceHidden(true, for: id)

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0
        ) {
            flying.transform = .identity
            flying.frame = destination.frame
            flying.layer.cornerRadius = 0
            root.alpha = 0
        } completion: { _ in
            self.source?.setZoomSourceHidden(false, for: id)
            self.finish()
        }
    }

    private func cancel(in root: UIView) {
        guard let flying else { return }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0
        ) {
            flying.transform = .identity
            flying.frame = self.startFrame
            root.alpha = 1
        } completion: { _ in
            self.hiddenPhoto?.isHidden = false
            self.hiddenPhoto = nil
            flying.removeFromSuperview()
            self.flying = nil
        }
    }

    /// Menutup TANPA animasi bawaan: animasinya sudah selesai dijalankan sendiri,
    /// dan menyerahkannya lagi ke animator hanya akan menerbangkan foto kedua.
    private func finish() {
        presented?.dismiss(animated: false)
        hiddenPhoto?.isHidden = false
        hiddenPhoto = nil
        flying?.removeFromSuperview()
        flying = nil
    }

    // MARK: Gestur

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let root = presented?.view,
              photoZoomDismissAllowed(in: root)
        else { return false }

        // Hanya tarikan ke BAWAH, dan yang jelas-jelas vertikal — usapan
        // menyamping itu milik pager antar foto.
        let velocity = pan.velocity(in: root)
        return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
