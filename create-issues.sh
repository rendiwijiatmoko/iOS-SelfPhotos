#!/usr/bin/env bash
#
# create-issues.sh — Buat GitHub-style issues di Gitea/Forgejo untuk project Immich iOS.
# Jalankan DI TERMINAL KOMPUTERMU (Claude Code CLI / Terminal biasa), bukan di cloud.
#
# Cara pakai:
#   1. Buat Access Token di web git server kamu:
#        Settings -> Applications -> Generate New Token (scope minimal: write:issue / repo)
#   2. Export env berikut, lalu jalankan skrip:
#        export GIT_HOST="https://git.0xmwehehe.xyz"
#        export GIT_OWNER="0xmwehehe"
#        export GIT_REPO="iOS-Immich"
#        export GIT_TOKEN="xxxxxxxxxxxxxxxxx"
#        bash create-issues.sh
#
# Aman diulang? TIDAK sepenuhnya — menjalankan 2x akan membuat issue duplikat.
# Jalankan sekali saja. (API Gitea/Forgejo: POST /api/v1/repos/{owner}/{repo}/issues)

set -euo pipefail

: "${GIT_HOST:?set GIT_HOST, mis: https://git.0xmwehehe.xyz}"
: "${GIT_OWNER:?set GIT_OWNER, mis: 0xmwehehe}"
: "${GIT_REPO:?set GIT_REPO, mis: iOS-Immich}"
: "${GIT_TOKEN:?set GIT_TOKEN dari Settings > Applications}"

API="${GIT_HOST}/api/v1/repos/${GIT_OWNER}/${GIT_REPO}/issues"

create_issue () {
  local title="$1"; local body="$2"
  echo "-> Membuat issue: ${title}"
  # jq -Rs mengubah body multiline jadi JSON string yang aman
  local payload
  payload=$(jq -n --arg t "$title" --arg b "$body" '{title:$t, body:$b}')
  curl -sf -X POST "$API" \
    -H "Authorization: token ${GIT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null && echo "   OK" || echo "   GAGAL (cek token/URL)"
}

# ----------------------------------------------------------------------------
# Satu issue per FASE. Body = checklist tugas + acceptance criteria.
# ----------------------------------------------------------------------------

create_issue "Fase 0 — Setup Proyek Xcode" "$(cat <<'EOF'
Tujuan: Proyek kosong bisa di-build & jalan di simulator iOS 26.

Tasks:
- [ ] New Project: iOS App, SwiftUI, Swift, Storage None
- [ ] Minimum Deployment iOS 26.0; Swift Language Version 6
- [ ] Buat struktur folder (App/Core/Models/Features/DesignSystem/Resources)
- [ ] Tambah enum LoadingPhase
- [ ] .gitignore Xcode + commit awal
- [ ] Skeleton ImmichApp + AppRouter (login vs main)

Acceptance: App jalan di simulator, tanpa warning concurrency.
EOF
)"

create_issue "Fase 1 — Networking Layer" "$(cat <<'EOF'
Tujuan: Panggil endpoint apa pun dengan aman, token otomatis, error tertangani.

Tasks:
- [ ] APIError (invalidURL/notConnected/unauthorized/decoding/server/unknown) — pesan default English
- [ ] Endpoint (path/method/query/body/headers) + helper .json
- [ ] APIClient: send<T>, sendVoid, rawData; auto auth header; validate status; JSONDecoder ISO8601
- [ ] Unit test dengan URLProtocol mock (opsional)

Acceptance: GET /server/ping balas {"res":"pong"}; error 401/500 rapi.
EOF
)"

create_issue "Fase 2 — Data Models (DTO)" "$(cat <<'EOF'
Tujuan: Struct Swift cocok dengan JSON API.

Tasks:
- [ ] AuthDTO (LoginRequest/LoginResponse), UserResponseDTO
- [ ] ServerPing/Features/About DTO
- [ ] AssetResponseDTO + ExifDTO
- [ ] TimeBucketDTO + TimelineBucketDTO (format columnar) + AssetLite (domain)
- [ ] AlbumResponseDTO, PersonDTO, SearchRequest/Response DTO, MemoryDTO
- [ ] Unit test decode JSON contoh dari Swagger

Catatan: verifikasi schema di https://<server>/api/spec.json
Acceptance: semua DTO compile; test decode sukses.
EOF
)"

create_issue "Fase 3 — Onboarding (Server URL + Login)" "$(cat <<'EOF'
Tujuan: Input server, login, token tersimpan aman, masuk layar utama.
Endpoint: /server/ping, /server/features, /auth/login, /auth/validateToken, /users/me, /auth/logout

Tasks:
- [ ] KeychainStore (save/read/delete)
- [ ] SessionManager (setServer/ping/features/loginPassword/loginApiKey/restore/logout)
- [ ] Layar Server URL (ping + features)
- [ ] Layar Login email/password
- [ ] Login via API Key (validasi /users/me)
- [ ] Restore session saat app start (validateToken)
- [ ] Logout
- [ ] (Opsional) OAuth via ASWebAuthenticationSession + URL scheme

Acceptance: login->masuk app; tutup-buka tetap login; kredensial salah->error rapi; logout->balik onboarding.
EOF
)"

create_issue "Fase 4 — Timeline (Grid Foto Utama)" "$(cat <<'EOF'
Tujuan: Grid semua foto per bulan, scroll cepat, thumbnail lazy + placeholder blur.
Endpoint: /timeline/buckets, /timeline/bucket, /assets/{id}/thumbnail

Tasks:
- [ ] AuthImage + ImageCache (loader ber-auth; AsyncImage bawaan 401)
- [ ] TimelineRepository (buckets + bucket columnar->AssetLite; parse tanggal)
- [ ] TimelineViewModel (lazy load per section)
- [ ] TimelineView grid + sticky header + pull-to-refresh
- [ ] Placeholder blur via thumbhash
- [ ] Empty state & error state + retry
- [ ] (Opsional) date scrubber

Acceptance: grid urut terbaru->terlama per bulan; scroll ribuan foto mulus; tap->viewer.
EOF
)"

create_issue "Fase 5 — Asset Detail (Viewer)" "$(cat <<'EOF'
Tujuan: Foto/video full screen, swipe, zoom, info EXIF+peta, aksi.
Endpoint: /assets/{id}, thumbnail?size=preview, /original, PUT /assets/{id}, DELETE /assets, /download/asset/{id}

Tasks:
- [ ] Swipe antar asset (TabView .page)
- [ ] Load bertingkat preview -> original
- [ ] Pinch-zoom & double-tap
- [ ] Video via AVPlayer + AVURLAsset header auth
- [ ] Toolbar: share, favorite, archive, delete
- [ ] Panel info EXIF + peta MapKit
- [ ] Chip wajah -> People
- [ ] Share/Save original ke Photos
- [ ] Swipe-down tutup
- [ ] Sinkron perubahan balik ke grid

Acceptance: full screen; swipe; zoom mulus; video jalan; favorite/delete tercermin; info+peta tampil.
EOF
)"

create_issue "Fase 6 — Albums" "$(cat <<'EOF'
Tujuan: Lihat/buka/buat album, tambah/hapus foto.
Endpoint: GET/POST /albums, GET /albums/{id}, PUT/DELETE /albums/{id}/assets, DELETE /albums/{id}

Tasks:
- [ ] AlbumsListView (pisah Saya vs Dibagikan via shared)
- [ ] AlbumDetailView (reuse grid Fase 4)
- [ ] Buat album
- [ ] Tambah/hapus asset (multi-select di grid)
- [ ] Rename/hapus album

Acceptance: lihat, buka, buat album; tambah/hapus foto berfungsi.
EOF
)"

create_issue "Fase 7 — Search & Explore" "$(cat <<'EOF'
Tujuan: Cari teks bebas (smart), metadata, Explore.
Endpoint: POST /search/smart, /search/metadata, GET /search/explore, /search/suggestions

Tasks:
- [ ] SearchView + .searchable (default smart, fallback metadata)
- [ ] Hasil grid + paginasi (nextPage)
- [ ] Explore page (kota & things)
- [ ] Filter metadata (tanggal, tipe, favorit, kota)
- [ ] Autocomplete via suggestions

Acceptance: ketik kata -> foto relevan; filter jalan.
EOF
)"

create_issue "Fase 8 — People / Faces" "$(cat <<'EOF'
Tujuan: Daftar orang, foto per orang, beri nama, sembunyikan.
Endpoint: GET /people, /people/{id}, /people/{id}/thumbnail, PUT /people/{id}

Tasks:
- [ ] PeopleView grid lingkaran wajah + nama
- [ ] PersonDetailView (foto orang; edit nama)
- [ ] Sembunyikan orang (isHidden)
- [ ] Integrasi chip wajah dari viewer

Acceptance: daftar orang tampil; buka foto per orang; beri/ubah nama.
EOF
)"

create_issue "Fase 9 — Memories" "$(cat <<'EOF'
Tujuan: "Hari ini X tahun lalu" ala stories.
Endpoint: GET /memories

Tasks:
- [ ] MemoriesView (baris kartu / tab)
- [ ] Story viewer auto-advance (tap kiri/kanan, tahan=pause)
- [ ] Tap asset -> viewer normal

Acceptance: memories muncul; story viewer mulus.
EOF
)"

create_issue "Fase 10 — Backup / Upload Foto dari HP" "$(cat <<'EOF'
Tujuan: Upload foto/video dari galeri dgn deteksi duplikat. Fase paling kompleks.
Endpoint: POST /assets (multipart), /assets/bulk-upload-check, GET /server/storage

Tasks:
- [ ] Izin PHPhotoLibrary + NSPhotoLibraryUsageDescription
- [ ] Pilih manual via PhotosPicker
- [ ] Export PHAsset -> file temp -> uploadAsset (multipart)
- [ ] Cek duplikat via bulk-upload-check
- [ ] Auto-backup: enumerasi PHAsset, antre, URLSession background
- [ ] UI progress (X dari Y, jeda/lanjut, hanya Wi-Fi)
- [ ] Retry gagal, lanjut item berikutnya, ringkasan

Acceptance (minimal): pilih foto -> terunggah -> muncul di timeline; duplikat tidak dobel.
EOF
)"

create_issue "Fase 11 — Settings & Profil" "$(cat <<'EOF'
Tujuan: Pusat pengaturan & info akun.
Endpoint: /users/me, /users/me/preferences, /server/about, /server/storage, /auth/logout

Tasks:
- [ ] Profil (foto, nama, email, admin, storage label)
- [ ] Penyimpanan (/server/storage)
- [ ] Backup settings (integrasi Fase 10)
- [ ] Tampilan (tema, jumlah kolom grid)
- [ ] Info server & versi app
- [ ] Logout & ganti server
- [ ] Bersihkan cache thumbnail

Acceptance: setelan tersimpan & berpengaruh.
EOF
)"

create_issue "Fase 12 — Sync & Cache Lokal (SwiftData)" "$(cat <<'EOF'
Tujuan: App cepat & bisa offline; delta sync hemat kuota.
Endpoint: POST /sync/full-sync, /sync/delta-sync

Tasks:
- [ ] ModelContainer + @Model (CachedAsset, BackupRecord, dll)
- [ ] Full sync pertama -> SwiftData
- [ ] Delta sync (updatedAfter/ackToken) -> merge
- [ ] UI baca cache dulu, refresh background (stale-while-revalidate)
- [ ] Cache thumbnail disk (LRU, batas ukuran)
- [ ] Offline mode + banner

Acceptance: buka tanpa internet -> foto terakhir tampil; sync berikut hanya perubahan.
EOF
)"

create_issue "Fase 13 — Polish, Aksesibilitas & Rilis" "$(cat <<'EOF'
Tujuan: Siap dipakai & didistribusikan.

Tasks:
- [ ] Desain iOS 26 (Liquid Glass, toolbar, Dark Mode)
- [ ] Aksesibilitas (VoiceOver, Dynamic Type)
- [ ] Haptics aksi penting
- [ ] Error/empty states konsisten
- [ ] Performance (Instruments: scroll 10k+ foto, cek leak cache)
- [ ] App Icon & Launch Screen
- [ ] Localization: String Catalog base English + tambah terjemahan id
- [ ] Privasi (App Privacy, ATS/HTTPS)
- [ ] TestFlight build + catatan rilis

Acceptance: stabil, cepat, aksesibel, siap distribusi.
EOF
)"

echo ""
echo "Selesai. Cek issues di: ${GIT_HOST}/${GIT_OWNER}/${GIT_REPO}/issues"
