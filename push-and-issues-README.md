# Cara Push Plan + Buat Issues (jalankan di TERMINAL komputermu)

Repo kamu: `https://git.0xmwehehe.xyz/0xmwehehe/iOS-Immich.git` (self-hosted, kemungkinan Gitea/Forgejo — **bukan GitHub**).

> Kenapa tidak bisa dari sesi Cowork ini: sisi komputer (device bridge) tidak punya akses jaringan untuk `git push`, dan sisi cloud tidak punya kredensial git kamu. Jadi langkah di bawah dijalankan langsung di terminal komputermu (atau lewat Claude Code CLI).

## Langkah 1 — Beresin lock file & commit PLAN.md

```bash
cd ~/Project/iOS-Immich

# hapus lock yang nyangkut (aman kalau tidak ada proses git jalan)
rm -f .git/index.lock

# taruh PLAN.md ke folder ini dulu (dari file yang Claude kirim), lalu:
git add PLAN.md
git commit -m "docs: rencana pembuatan app Immich iOS (SwiftUI, iOS 26)"
git push -u origin main
```

## Langkah 2 — Buat issues via API (satu issue per fase)

1. Buat Access Token di web git server: **Settings → Applications → Generate New Token** (scope: `write:issue` atau `repo`).
2. Jalankan:

```bash
export GIT_HOST="https://git.0xmwehehe.xyz"
export GIT_OWNER="0xmwehehe"
export GIT_REPO="iOS-Immich"
export GIT_TOKEN="PASTE_TOKEN_DISINI"

bash create-issues.sh
```

Butuh `jq` dan `curl` (biasanya sudah ada di macOS; kalau belum: `brew install jq`).
Skrip membuat **14 issues** (Fase 0–13), masing-masing berisi checklist tugas + acceptance criteria.

> ⚠️ Jalankan `create-issues.sh` **sekali saja** — mengulang akan bikin issue duplikat.

## Alternatif: pakai `tea` CLI (Gitea/Forgejo)

```bash
brew install tea
tea login add --url https://git.0xmwehehe.xyz --token <TOKEN>
# lalu bisa: tea issues create --title "..." --body "..."
```

## Kalau mau Claude yang mengerjakan langsung

Dua cara supaya Claude bisa commit/push/bikin issue untukmu:

1. **Claude Code CLI** di terminal komputermu — Claude punya akses penuh ke folder + kredensial git kamu, jadi bisa jalankan Langkah 1 & 2 di atas.
2. **Jalankan task ini "On your computer"** dari Claude Desktop app (picker "Run this task" di kanan atas saat memulai task Cowork). Mode ini bekerja langsung dengan folder & jaringan komputermu, jadi push & pemanggilan API issue bisa dilakukan tanpa batasan sandbox cloud.
