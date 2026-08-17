# Protokol Jembatan Stok SDRG → POS

POS (`point-of-sales-app-25e2b`) dan Sentra Distribusi Rejoso Gemilang
(`warehouse-375`) memakai proyek Firebase yang berbeda. Seperti pada
[protokol voucher e-Santren](e_santren_voucher_claim_protocol.md), tidak ada
transaksi lintas proyek. Alurnya satu arah dan hanya baca.

## Alur

1. Kasir SDRG memilih pelanggan terdaftar **Canteen375** saat checkout.
2. Di transaksi yang sama dengan penjualan, SDRG menulis
   `deliveries_canteen375/{orderId}` berisi `base_qty` per produk.
3. POS membaca outbox itu lewat Firebase app sekunder bernama `warehouse-375`.
   POS **tidak pernah menulis** ke proyek SDRG.
4. `SdrgAutoAcceptService` menerapkan pengiriman tersebut **tanpa perlu
   ditekan** — begitu dilihat, stok langsung bertambah di dalam transaksi POS,
   bersama dokumen idempoten `Canteens/canteen375/Orders/sdrg_{orderId}_r{revisi}`
   dan catatan `Canteens/canteen375/SdrgDeliveries/{orderId}`. Layanan ini
   berjalan sejak aplikasi POS dibuka (`main.dart`), bukan hanya saat tab
   **Penerimaan SDRG** dilihat, sehingga tidak bergantung pada operator sedang
   membuka tab tersebut.

Karena catatan penerimaan disimpan di proyek POS sendiri, tidak diperlukan
kredensial tulis lintas proyek maupun service account.

### Yang tetap perlu orang

Otomatis bukan berarti tanpa pengecualian. Tiga hal berikut tetap tampil di
tab **Penerimaan SDRG** menunggu tindakan, karena tidak bisa ditebak dengan
aman:

- **Produk belum ditautkan**, **satuan berubah**, atau **jumlah tidak bulat**
  (lihat "Yang diblokir, bukan ditebak" di bawah) — begitu diperbaiki,
  `SdrgAutoAcceptService.reconcileNow()` langsung memeriksa ulang tanpa
  menunggu perubahan lain.
- **Pembatalan yang akan membuat stok negatif** — biasanya karena bahannya
  sudah terpakai. Membalikkan stok begitu saja tanpa dilihat lebih berisiko
  daripada meminta satu keputusan, jadi ini sengaja tidak dibuat otomatis.

## Revisi dan pembatalan

`revision` pada outbox naik setiap SDRG mengubah atau membatalkan pesanan.
POS menyimpan `acceptedRevision`, dan hanya menerapkan **selisihnya**:

```
target = dibatalkan ? {} : jumlah per bahan
delta  = target - appliedByPosItem
```

`appliedByPosItem` dikunci per bahan Inventory POS, bukan per baris SDRG, agar
tetap benar meskipun tautan produk diperbaiki di kemudian hari. Dokumen idempoten
dibuat **per revisi**; satu dokumen per pesanan akan membuat penerapan revisi
kedua tertelan sebagai "sudah diproses".

Pembatalan yang aman diterapkan otomatis seperti biasa. Hanya pembatalan yang
akan membuat stok negatif yang berhenti menunggu orang — operator memilih
menerapkan tetap atau mencatat saja (`state: reversalPending`) agar selisihnya
bisa ditutup lewat stock count.

## Yang diblokir, bukan ditebak

- **Produk belum ditautkan** — tidak ada bahan Inventory yang cocok.
- **Satuan berubah** — `base_unit` SDRG berbeda dari saat tautan dibuat.
- **Jumlah tidak bulat** — stok POS bertipe `int`. Pembulatan ke bawah
  menghilangkan stok, ke atas menciptakan stok, dan keduanya tidak terlihat.
  Penjumlahan per bahan dilakukan **sebelum** pemeriksaan, sehingga dua produk
  SDRG yang menuju satu bahan POS tetap dapat diterima.

## Tautan produk: SDRG membaca Inventory POS langsung

Untuk memilih bahan POS yang sepadan dengan sebuah produk SDRG, aplikasi web
SDRG **membaca `Canteens/canteen375/Inventory` milik POS secara langsung**,
lewat Cloud Function `listPosInventory` (khusus superadmin). Ini arah yang
berbeda dari outbox pengiriman di atas — bukan POS membaca SDRG, melainkan
SDRG membaca POS — dan sengaja tidak memakai mekanisme yang sama.

Bedanya penting: **kredensial ini hidup di backend SDRG (Cloud Functions),
bukan di browser.** Sebuah login yang dipakai situs web tidak bisa dijaga
rahasia — apa pun yang dipegang browser dapat diekstrak pengunjung. Cloud
Function berjalan di server dan tidak pernah dikirim ke klien mana pun,
sehingga service account POS ini aman disimpan sebagai secret meski situs
webnya publik.

```
SDRG Cloud Function (listPosInventory, savePosProductLink)
  ── service account, hanya di server ──▶  POS Inventory
```

- `listPosInventory` — daftar `{id, name, unit}` untuk dropdown tautan.
- `savePosProductLink` — memvalidasi `inventory_item_id` terhadap Inventory
  POS yang sesungguhnya sebelum menyimpan tautan; nama dan satuan disalin dari
  sana, bukan dari input klien.

Kredensial disimpan sebagai Secret Manager secret `POS_SERVICE_ACCOUNT_KEY`,
diikat hanya ke dua callable di atas:

```
firebase functions:secrets:set POS_SERVICE_ACCOUNT_KEY --project warehouse-375
```

Nilainya adalah isi JSON kunci service account POS (Firebase Console proyek
`point-of-sales-app-25e2b` → Project Settings → Service Accounts → Generate
new private key). Kunci ini tidak pernah masuk ke repo maupun ke bundel web.

Tautan yang tersimpan (`pos_product_links`) tetap dibaca POS lewat akun
jembatan seperti biasa (lihat "Lingkungan" di bawah) — hanya *pencarian
nama bahan* yang berubah arah, bukan alur penerimaan pengiriman.

## Checklist penyediaan

Sampai jembatan aktif, tab **Penerimaan SDRG** menampilkan pesan
"Sambungan SDRG belum diaktifkan". Bagian lain aplikasi tidak terpengaruh.

- [x] **Akun jembatan** — `bridge@warehouse375.com` di proyek `warehouse-375`.
- [x] **Peran read-only** — `users/7H4EplY9JIedIdNXI1Of4Y8OmmA3` =
      `{ role: 'bridge' }`. Peran `bridge` tidak ada di allow-list callable mana
      pun, sehingga akun ini tidak dapat mengubah data walaupun rules
      dilonggarkan.
- [x] **Akses outbox** — UID tersebut sudah dipasang pada `isPosBridge()` di
      `firestore.rules` SDRG.
- [x] **Deploy functions SDRG** — 16 Agustus 2026, 4 callable baru
      (`createCustomer`, `updateCustomer`, `archiveCustomer`,
      `rebuildDeliveryOutbox`) dan 11 pembaruan. Binding
      `roles/run.invoker` untuk `allUsers` sudah dipasang otomatis oleh
      Firebase CLI 15.26 — langkah gcloud manual tidak lagi diperlukan.
- [x] **Deploy rules SDRG** — ruleset aktif sudah memuat UID jembatan.
- [ ] **Deploy aplikasi web SDRG** (Vercel) agar halaman Pelanggan tersedia.
- [ ] **Pelanggan Canteen375** — lewat halaman **Pelanggan** di aplikasi SDRG
      (khusus superadmin), dengan Sinkronisasi Stok = `canteen375`.
- [ ] **Service account POS** — generate kunci baru (jangan pakai kunci yang
      sudah pernah ter-commit ke repo POS), simpan sebagai secret
      `POS_SERVICE_ACCOUNT_KEY` di functions SDRG, lalu
      `firebase deploy --only functions --project warehouse-375` agar
      `listPosInventory`/`savePosProductLink` terikat ke secret tersebut.
- [ ] **Kredensial jembatan** — buat `lib/Services/SdrgBridgeCredentials.dart`
      (repo POS ini **publik**, jadi file ini sengaja masuk `.gitignore` dan
      tidak pernah dikirim ke GitHub):

      ```dart
      const String sdrgBridgePassword = 'password123';
      ```

      Sekali dibuat di suatu mesin, berlaku seterusnya di mesin itu —
      `flutter run` / `flutter run --release` berjalan tanpa flag tambahan
      apa pun. `bridgeEmail` (`bridge@warehouse375.com`, bukan rahasia)
      tetap langsung di `SdrgBridgeService.dart`.

      **Wajib dibuat di setiap mesin/CI baru** — tanpa file ini, `import`-nya
      di `SdrgBridgeService.dart` gagal dan seluruh aplikasi tidak bisa
      dikompilasi, bukan hanya fitur jembatan yang nonaktif.

> Peran `bridge` pada akun ini tidak ada di allow-list callable mana pun di
> SDRG, sehingga akun ini tidak dapat mengubah data walaupun kredensialnya
> bocor — hanya dapat membaca outbox-nya sendiri. Jangan pakai ulang password
> ini di tempat lain, dan jika perlu diganti, cukup ubah isi file lokal
> tersebut di setiap mesin yang memakainya.

## Lingkungan

Mode testing POS (`Col.testingMode`) membaca `deliveries_canteen375_test`, yaitu
pasangan dari environment `staging` di SDRG. Mode normal membaca
`deliveries_canteen375`.

## Pemulihan

Callable superadmin `rebuildDeliveryOutbox` di SDRG menulis ulang outbox sebuah
pesanan dari dokumen order-nya. Gunakan untuk pesanan yang dibuat sebelum
jembatan ada, atau jika dokumen outbox hilang.
