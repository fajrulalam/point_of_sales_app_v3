# Protokol Klaim Voucher e-Santren

POS dan e-santren memakai proyek Firebase yang berbeda. Karena itu klaim
voucher tidak boleh dilakukan sebagai satu transaksi lintas proyek. Implementasi
POS memakai dua fase berikut.

## Fase reservasi

Sebelum transaksi POS dimulai, POS menjalankan transaksi di proyek e-santren:

- Membaca `vouchers/{voucherCode}` dan menolak data tanpa tanggal, nilai,
  status, atau tipe penggunaan yang valid.
- Membuat atau membaca marker idempoten
  `operationClaims/{operationId}`.
- Menyimpan `status: reserved`, `voucherCode`, `amount`, dan
  `reservationExpiresAt` (15 menit).
- Untuk voucher sekali pakai, menyimpan `reservedOperationId`.
- Untuk voucher multi-pakai, menyimpan `reservedAmount` dan
  `reservationAmounts.{operationId}`, serta
  `reservationExpiries.{operationId}` agar reservasi yang ditinggalkan dapat
  kedaluwarsa tanpa mengunci seluruh saldo voucher.

Reservation harus gagal jika voucher tidak aktif, sudah diklaim, kedaluwarsa,
atau saldo yang tidak dicadangkan tidak mencukupi. Kegagalan ini hanya
menghentikan pembayaran dengan voucher tersebut.

## Commit POS dan finalisasi

Transaksi POS menulis penjualan, stok, poin member, voucher lokal, dan
`externalVoucherClaims/{operationId}` dengan status `pending` secara atomik.

Setelah commit POS berhasil, POS menjalankan transaksi e-santren kedua:

- Memastikan marker masih `reserved`, belum kedaluwarsa, dan dimiliki oleh
  `operationId` yang sama.
- Mengubah voucher menjadi `CLAIMED` atau mengurangi saldo multi-pakai.
- Mengubah marker menjadi `completed`.

Jika finalisasi gagal, penjualan POS tetap tersimpan. Outbox lokal diubah menjadi
`failed` dan harus dapat dicoba ulang oleh administrator. Retry hanya boleh
menggunakan `operationId` yang sama dan harus idempoten.

## Persyaratan rules e-santren

POS tidak login ke proyek e-santren, sehingga POS mengaksesnya sebagai klien
anonim. Rules e-santren (`firebase-rules/transition/firestore.rules` dan
`firebase-rules/lockdown/firestore.rules` di repo e-santren, diuji di
`tests/security-rules.emulator.cjs`) mengizinkan klien anonim hanya untuk
langkah-langkah protokol ini:

- `voucherGroup/{id}`: `get` saja (cek kampanye aktif) dan menaikkan
  `totalRedemptions` / `totalClaimed` tepat satu. `list`, membuat, dan menghapus
  hanya untuk super admin.
- `operationClaims/{operationId}`: `get`; dibuat dengan `operationId` sama dengan
  ID dokumen, status `reserved`, jumlah bulat > 0 yang tidak melebihi saldo
  voucher, dan voucher harus ada. Transisi yang diizinkan hanya
  `reserved -> completed | released` dan `released -> reserved` (retry). Marker
  `completed` tidak dapat berubah lagi dan penghapusan selalu ditolak.
- `vouchers/{code}`: hanya field reservasi dan klaim yang boleh berubah, dan
  hanya pada voucher yang belum `CLAIMED` / `DISABLED` / `EXPIRED`. Saldo hanya
  boleh turun dan tidak boleh negatif; status hanya boleh menjadi `CLAIMED`.
  Setiap klaim harus menyebut marker `reserved` yang belum kedaluwarsa untuk
  voucher yang sama, marker itu harus menjadi `completed` pada commit yang sama
  (satu reservasi hanya untuk satu klaim), dan penurunan saldo harus sama
  dengan `amount` marker. Membuat dan menghapus voucher hanya untuk super admin.

Batasan yang diterima: karena klien anonim, siapa pun yang memegang konfigurasi
web publik proyek e-santren dapat mengirim urutan tulis yang sama. Rules menjaga
konsistensi data (voucher hanya berkurang lewat reservasi yang cocok), tetapi
tidak membuktikan bahwa pemanggilnya adalah POS. Jika POS kelak memakai
identitas login, ubah `isPosClient()` di rules e-santren.

Setelah mengubah rules di repo e-santren, rules harus dipublikasikan ke proyek
e-santren dengan `firebase deploy --only firestore:rules`.
