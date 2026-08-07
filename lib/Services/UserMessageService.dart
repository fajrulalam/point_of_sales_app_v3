import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// Converts technical exceptions and legacy English messages into short,
/// cashier-friendly Indonesian messages. Detailed exceptions remain available
/// in the developer log; they are never shown directly in the UI.
class UserMessageService {
  UserMessageService._();

  static String fromError(
    Object? error, {
    String fallback = 'Terjadi kesalahan. Silakan coba lagi.',
  }) {
    if (error == null) return fallback;

    if (error is FirebaseAuthException) {
      return _firebaseAuthMessage(error.code);
    }
    if (error is FirebaseException) {
      return _firebaseMessage(error.code);
    }
    if (error is TimeoutException) {
      return 'Koneksi terlalu lama. Silakan coba lagi.';
    }
    if (error is SocketException) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi internet.';
    }
    if (error is PlatformException) {
      return _platformMessage(error.code);
    }

    final raw =
        error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    if (raw.isEmpty || raw == 'null' || raw.startsWith('Instance of ')) {
      return fallback;
    }
    return fromText(raw, fallback: fallback);
  }

  /// Translates a stored/service message while preserving messages that are
  /// already written in Indonesian.
  static String fromText(
    String? message, {
    String fallback = 'Terjadi kesalahan. Silakan coba lagi.',
  }) {
    final raw = message?.trim();
    if (raw == null || raw.isEmpty || raw == 'null') return fallback;

    final lower = raw.toLowerCase();
    final missingIngredient = RegExp(
      r'ingredient\s+"([^"]+)"\s+not found in inventory',
      caseSensitive: false,
    ).firstMatch(raw);
    if (missingIngredient != null) {
      return 'Bahan "${missingIngredient.group(1)}" tidak ditemukan di stok';
    }
    if (lower.contains('chain validation failed') ||
        lower.contains('sslhandshakeexception')) {
      return 'Koneksi aman ke server gagal. Periksa tanggal, waktu, dan koneksi internet perangkat.';
    }
    if (lower.contains('permission-denied') ||
        lower.contains('missing or insufficient permissions') ||
        lower.contains('permission denied')) {
      return 'Akses ditolak. Periksa akun dan izin aplikasi.';
    }
    if (lower.contains('network-request-failed') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('network error') ||
        lower.contains('unable to resolve host')) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi internet.';
    }
    if (lower.contains('deadline-exceeded') ||
        lower.contains('timed out') ||
        lower.contains('timeout')) {
      return 'Koneksi terlalu lama. Silakan coba lagi.';
    }
    if (lower.contains('not-found') || lower.contains('not found')) {
      return 'Data tidak ditemukan.';
    }
    if (lower.contains('does not exist') ||
        lower.contains('could not be resolved') ||
        lower.contains('cannot be resolved') ||
        lower.contains('references missing') ||
        lower.contains('has no valid inventory reference')) {
      return 'Referensi data tidak ditemukan.';
    }
    if (lower.contains('non-positive') || lower.contains('invalid quantity')) {
      return 'Jumlah data tidak valid.';
    }
    if (lower.contains('became negative')) {
      return 'Stok menjadi negatif.';
    }
    if (lower.contains('was skipped')) {
      return 'Data tidak valid dan dilewati.';
    }
    if (lower.contains('exact legacy name') ||
        lower.contains('instead of stable ids')) {
      return 'Data menggunakan referensi nama lama.';
    }
    if (lower.contains('not keyed as')) {
      return 'Format kunci log stok tidak sesuai.';
    }
    if (lower.contains('already-exists') || lower.contains('already exists')) {
      return 'Data sudah ada.';
    }
    if (lower.contains('failed-precondition')) {
      return 'Data belum siap diproses. Muat ulang lalu coba lagi.';
    }
    if (lower.contains('aborted') || lower.contains('conflict')) {
      return 'Data berubah di perangkat lain. Muat ulang lalu coba lagi.';
    }
    if (lower.contains('unauthenticated') || lower.contains('unauthorized')) {
      return 'Sesi login berakhir. Silakan masuk kembali.';
    }
    if (lower.contains('resource-exhausted')) {
      return 'Server sedang sibuk. Silakan coba lagi beberapa saat.';
    }
    if (lower.contains('internal error') || lower.contains('internal')) {
      return 'Terjadi kesalahan pada server. Silakan coba lagi.';
    }
    if (lower.contains('invalid-argument') ||
        lower.contains('invalid argument')) {
      return 'Data yang dimasukkan tidak valid.';
    }
    if (lower.contains('no appcheckprovider installed')) {
      return 'Pemeriksaan keamanan aplikasi belum tersedia.';
    }

    // Known application messages are already suitable for the cashier.
    if (_containsIndonesianWord(lower)) return raw;

    // Do not expose an unknown English SDK message to the cashier.
    final looksTechnical = RegExp(
      r'\b(error|exception|failed|failure|unable|invalid|missing|could not|cannot|please|unknown|status code|rpc)\b',
      caseSensitive: false,
    ).hasMatch(raw);
    return looksTechnical ? fallback : raw;
  }

  static bool _containsIndonesianWord(String text) {
    const words = [
      'tidak',
      'gagal',
      'terjadi',
      'pesanan',
      'stok',
      'bahan',
      'data',
      'voucher',
      'akun',
      'sudah',
      'belum',
      'silakan',
      'masukkan',
      'pilih',
      'jumlah',
      'dapat',
      'harus',
      'kurang',
      'tidak ditemukan',
    ];
    return words.any(text.contains);
  }

  static String _firebaseAuthMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Format email tidak valid.';
      case 'user-disabled':
        return 'Akun ini dinonaktifkan.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau kata sandi salah.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Coba lagi nanti.';
      case 'network-request-failed':
        return 'Tidak dapat terhubung ke server. Periksa koneksi internet.';
      case 'operation-not-allowed':
        return 'Metode login ini belum diaktifkan.';
      case 'requires-recent-login':
        return 'Sesi login sudah kedaluwarsa. Silakan masuk kembali.';
      case 'internal-error':
        return 'Terjadi kesalahan pada server login. Silakan coba lagi.';
      default:
        return 'Login gagal. Periksa koneksi lalu coba lagi.';
    }
  }

  static String _firebaseMessage(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Akses ditolak. Periksa akun dan izin aplikasi.';
      case 'unavailable':
        return 'Server tidak tersedia. Periksa koneksi internet lalu coba lagi.';
      case 'deadline-exceeded':
        return 'Koneksi terlalu lama. Silakan coba lagi.';
      case 'not-found':
        return 'Data tidak ditemukan.';
      case 'already-exists':
        return 'Data sudah ada.';
      case 'failed-precondition':
        return 'Data belum siap diproses. Muat ulang lalu coba lagi.';
      case 'aborted':
        return 'Data berubah di perangkat lain. Muat ulang lalu coba lagi.';
      case 'unauthenticated':
        return 'Sesi login berakhir. Silakan masuk kembali.';
      case 'resource-exhausted':
        return 'Server sedang sibuk. Silakan coba lagi beberapa saat.';
      default:
        return 'Terjadi kesalahan pada server. Silakan coba lagi.';
    }
  }

  static String _platformMessage(String code) {
    switch (code.toLowerCase()) {
      case 'network_error':
      case 'network-request-failed':
        return 'Tidak dapat terhubung ke server. Periksa koneksi internet.';
      case 'permission_denied':
        return 'Akses ditolak. Periksa izin aplikasi.';
      default:
        return 'Fitur tidak dapat digunakan saat ini. Silakan coba lagi.';
    }
  }
}
