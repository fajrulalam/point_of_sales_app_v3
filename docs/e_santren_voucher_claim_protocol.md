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

Aturan Firestore di proyek e-santren harus menjamin bahwa:

- Hanya identitas POS administrator yang dapat menulis voucher,
  `operationClaims`, dan counter campaign.
- `operationClaims/{operationId}` hanya dapat dibuat/diperbarui dengan
  `operationId` yang sama dengan ID dokumen.
- Marker `completed` tidak dapat dikembalikan ke `reserved`, `pending`, atau
  `failed`.
- Voucher sekali pakai hanya dapat difinalisasi oleh operation ID yang sedang
  dicadangkan.
- Voucher multi-pakai hanya dapat mengurangi reservation milik operation ID
  tersebut dan tidak boleh menghasilkan saldo negatif.
- Penghapusan voucher, marker operasi, dan riwayat klaim ditolak.

File ini adalah kontrak deployment untuk proyek e-santren. Rules proyek POS
berada di `firestore.rules`; rules e-santren harus diterapkan di proyek
eksternal setelah skema field dan daftar administrator dikonfirmasi.
