# Dynamic Island untuk Windows

Pil kecil di atas layar Windows yang meniru Dynamic Island di iPhone/Mac. Arahkan kursor ke pil, ia membesar dan menampilkan musik, jam, dan alat-alat kecil. Selain itu, ia memberi tahu hal-hal penting tanpa mengganggu.

Dibuat dengan Electron, ditambah skrip PowerShell untuk membaca status Windows.

## Fitur

- **Musik**: judul, sampul album, progres lagu, dan tombol putar/jeda/lompat untuk Spotify, YouTube di browser, dll. Klik bar progres untuk lompat ke bagian lagu.
- **Lirik berjalan**: lirik tersinkron dari [LRCLIB](https://lrclib.net). Klik baris lirik untuk lompat ke bagian itu, dan lirik bisa ditampilkan di pil kecil.
- **Volume & kecerahan**: slider, scroll mouse di atas pil, dan bar notifikasi ala iPhone saat nilainya berubah
- **Jam, tanggal, kalender, baterai, WiFi**
- **Timer fokus (Pomodoro)**: 25/5/15 menit, hitung mundurnya tampil di pil
- **Pengingat minum**: catat ml yang diminum, target harian, pengingat tiap jam
- **To-do**: tugas dengan jam pengingat
- **Shelf**: tarik file ke pil untuk disimpan sementara, lalu tarik keluar ke chat, email, atau folder
- **Notifikasi kecil**: teks disalin, charger dicolok/dilepas, WiFi putus/tersambung, Caps Lock
- **Maskot mata** muncul saat komputer diam
- Otomatis sembunyi saat ada aplikasi layar penuh
- Bisa digeser ke mana saja (posisinya diingat), 5 pilihan warna, bisa jalan otomatis saat Windows menyala

## Cara menjalankan

Butuh [Node.js](https://nodejs.org) dan Windows 10/11.

```bash
npm install
npm start
```

Setelah `npm install`, klik dua kali `Jalankan Dynamic Island.vbs` untuk menjalankannya tanpa jendela terminal.

Pengaturan ada di ikon bulat putih di system tray (pojok kanan bawah): sembunyikan, kembalikan ke tengah, warna, maskot, jalankan saat Windows menyala, dan keluar.

## Cara kerjanya

| File | Isi |
|---|---|
| `main.js` | Jendela transparan selalu di atas, klik tembus di luar pil, tray, shelf, deteksi layar penuh |
| `index.html` | Seluruh tampilan dan animasi island |
| `preload.js` | Jembatan antara tampilan dan proses utama |
| `media.ps1` | Membaca lagu yang diputar (Windows Media Session) dan menjalankan perintah putar/jeda/lompat |
| `system.ps1` | Membaca volume, kecerahan, WiFi, Caps Lock, dan aplikasi layar penuh |

Data to-do, minum, dan shelf disimpan di komputer sendiri (`%APPDATA%\dynamic-island`). Satu-satunya koneksi keluar adalah ke LRCLIB untuk mencari lirik, dan yang dikirim hanya judul, artis, dan durasi lagu.

Terinspirasi dari [Nusa](https://rama2555.github.io/nusa/).
