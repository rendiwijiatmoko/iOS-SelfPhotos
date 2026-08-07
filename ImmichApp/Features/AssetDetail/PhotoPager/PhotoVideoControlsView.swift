import SwiftUI
import UIKit

/// Keadaan pemutaran yang perlu diketahui bar kontrol.
struct PhotoPlaybackState: Equatable {
    var isVideo = false
    var isPlaying = false
    var isMuted = false
    /// Detik yang sudah berjalan.
    var time: Double = 0
    var duration: Double = 0
    /// Bagian file yang sudah tersedia untuk diputar, 0…1.
    var bufferedFraction: Float = 0

    var fraction: Float {
        guard duration > 0 else { return 0 }
        return Float(min(max(time / duration, 0), 1))
    }
}

/// Yang dikabari pager setiap keadaan pemutaran berubah.
@MainActor
protocol PhotoPlaybackObserver: AnyObject {
    func playbackDidUpdate(_ state: PhotoPlaybackState)
}

/// Bar kontrol video: putar/jeda, geser posisi, dan bisu.
///
/// Kontrolnya bawaan semua — `UISlider` dan SF Symbols — bukan gambar sendiri,
/// jadi perilakunya (area sentuh, umpan balik tekan, dukungan aksesibilitas)
/// sama persis dengan yang diharapkan di iOS.
struct PhotoVideoControlsView: UIViewRepresentable {
    /// Pager yang memegang pemutarnya.
    ///
    /// Disambungkan LANGSUNG, tanpa melewati `@State`: posisi pemutaran berubah
    /// beberapa kali per detik, dan menyalurkannya lewat SwiftUI berarti
    /// membangun ulang seluruh body layar detail sesering itu juga.
    let pager: PhotoPagerController

    func makeUIView(context: Context) -> PhotoVideoControlsBar {
        let bar = PhotoVideoControlsBar()
        bar.attach(to: pager)
        return bar
    }

    func updateUIView(_ bar: PhotoVideoControlsBar, context: Context) {
        bar.attach(to: pager)
    }
}

final class PhotoVideoControlsBar: UIView {
    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let playButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let slider = UISlider()
    private let bufferProgress = UIProgressView(progressViewStyle: .default)

    private weak var pager: PhotoPagerController?
    private var state = PhotoPlaybackState()
    /// true selagi jari memegang slider — selama itu posisi dari pemutar
    /// diabaikan, kalau tidak nilainya tarik-menarik dengan jari.
    private var isScrubbing = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        background.clipsToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)

        muteButton.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)

        slider.minimumValue = 0
        slider.maximumValue = 1
        // Track kosong transparan supaya progres unduhan di belakang slider
        // tetap terlihat. Bagian yang sudah ditonton digambar oleh minimumTrack.
        slider.maximumTrackTintColor = .clear
        slider.addTarget(self, action: #selector(scrubbingBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubbed), for: .valueChanged)
        slider.addTarget(
            self, action: #selector(scrubbingEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel])

        bufferProgress.trackTintColor = UIColor.secondaryLabel.withAlphaComponent(0.22)
        bufferProgress.translatesAutoresizingMaskIntoConstraints = false

        let timeline = UIView()
        timeline.addSubview(bufferProgress)
        slider.translatesAutoresizingMaskIntoConstraints = false
        timeline.addSubview(slider)
        NSLayoutConstraint.activate([
            bufferProgress.leadingAnchor.constraint(equalTo: timeline.leadingAnchor),
            bufferProgress.trailingAnchor.constraint(equalTo: timeline.trailingAnchor),
            bufferProgress.centerYAnchor.constraint(equalTo: timeline.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: timeline.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: timeline.trailingAnchor),
            slider.topAnchor.constraint(equalTo: timeline.topAnchor),
            slider.bottomAnchor.constraint(equalTo: timeline.bottomAnchor),
        ])

        let stack = UIStackView(arrangedSubviews: [playButton, timeline, muteButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Tombolnya tidak boleh ikut melar; yang mengisi sisa lebar adalah
        // slider-nya.
        playButton.setContentHuggingPriority(.required, for: .horizontal)
        muteButton.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.layer.cornerRadius = bounds.height / 2
        bufferProgress.progressTintColor = tintColor
    }

    func attach(to pager: PhotoPagerController) {
        guard self.pager !== pager else { return }
        self.pager = pager
        pager.playbackObserver = self
        pager.reportPlaybackState()
    }

    // MARK: - Aksi

    @objc private func togglePlay() {
        pager?.togglePlayback()
    }

    @objc private func toggleMute() {
        pager?.toggleMute()
    }

    @objc private func scrubbingBegan() {
        isScrubbing = true
    }

    @objc private func scrubbed() {
        guard state.duration > 0 else { return }
        pager?.seek(toFraction: Double(slider.value))
    }

    @objc private func scrubbingEnded() {
        isScrubbing = false
    }
}

// MARK: - Keadaan

extension PhotoVideoControlsBar: PhotoPlaybackObserver {
    func playbackDidUpdate(_ state: PhotoPlaybackState) {
        self.state = state

        let playSymbol = state.isPlaying ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: playSymbol), for: .normal)

        let muteSymbol = state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.setImage(UIImage(systemName: muteSymbol), for: .normal)

        slider.isEnabled = state.duration > 0
        bufferProgress.setProgress(state.bufferedFraction, animated: false)
        guard !isScrubbing else { return }
        slider.setValue(state.fraction, animated: false)
    }
}
