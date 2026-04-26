import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Screens/Home.dart';

class LoginScreen extends StatefulWidget {
  static const String id = 'LoginScreen';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _teal = Color(0xFF069494);
  static const _tealDark = Color(0xFF004D4D);
  static const _tealLight = Color(0xFFE0F4F4);
  static const _yellow = Color(0xFFF5C518);

  static const String _correctPin = '375375';
  static const String _adminEmail = 'admin@canteen375.com';
  static const String _adminPassword = 'password123';
  static const List<String> _employees = ['Ghinan', 'Amel', 'Eka', 'Dina'];

  String? _selectedEmployee;
  bool _dropdownOpen = false;
  String _enteredPin = '';
  bool _isLoading = false;
  String? _errorMessage;

  // Keys to measure dropdown position relative to the card
  final _cardKey = GlobalKey();
  final _employeeRowKey = GlobalKey();
  double _dropdownTopOffset = 246; // fallback

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureDropdownOffset());
  }

  void _measureDropdownOffset() {
    final cardBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    final rowBox = _employeeRowKey.currentContext?.findRenderObject() as RenderBox?;
    if (cardBox == null || rowBox == null) return;
    final rowGlobal = rowBox.localToGlobal(Offset.zero);
    final cardGlobal = cardBox.localToGlobal(Offset.zero);
    if (mounted) {
      setState(() {
        _dropdownTopOffset = (rowGlobal.dy - cardGlobal.dy) + rowBox.size.height;
      });
    }
  }

  void _onDigitTap(String digit) {
    if (_selectedEmployee == null || _enteredPin.length >= 6 || _isLoading) return;
    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });
    if (_enteredPin.length == 6) _validateAndLogin();
  }

  void _onDelete() {
    if (_enteredPin.isEmpty || _isLoading) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _validateAndLogin() async {
    if (_selectedEmployee == null) {
      setState(() {
        _errorMessage = 'Pilih kasir terlebih dahulu.';
        _enteredPin = '';
      });
      return;
    }

    if (_enteredPin != _correctPin) {
      setState(() {
        _errorMessage = 'PIN salah. Coba lagi.';
        _enteredPin = '';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _adminEmail,
        password: _adminPassword,
      );
      if (mounted) Navigator.pushReplacementNamed(context, Home.id);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message ?? 'Terjadi kesalahan saat login';
          _enteredPin = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && FirebaseAuth.instance.currentUser != null) {
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, Home.id);
        return;
      }
      if (mounted) {
        setState(() {
          _errorMessage = 'Terjadi kesalahan. Coba lagi.';
          _enteredPin = '';
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherEmployees = _employees.where((e) => e != _selectedEmployee).toList();


    return Scaffold(
      backgroundColor: _tealDark,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                child: Center(
                  child: Container(
                    key: _cardKey,
                    width: 360,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                // ── Main content column ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: _tealLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront_rounded, size: 48, color: _teal),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '375 POS Admin',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _tealDark,
                        ),
                      ),
                      Text(
                        'Pilih kasir yang bertugas',
                        style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      // Employee selector trigger (collapsed, never expands)
                      GestureDetector(
                        key: _employeeRowKey,
                        onTap: () => setState(() => _dropdownOpen = !_dropdownOpen),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedEmployee != null ? _tealLight : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedEmployee != null ? _teal : Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_selectedEmployee != null)
                                _buildAvatar(_selectedEmployee!, isSelected: true)
                              else
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person_outline, color: Colors.black38, size: 20),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedEmployee ?? 'Pilih kasir...',
                                  style: GoogleFonts.poppins(
                                    fontWeight: _selectedEmployee != null ? FontWeight.w600 : FontWeight.normal,
                                    fontSize: 15,
                                    color: _selectedEmployee != null ? _tealDark : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: _dropdownOpen ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: _selectedEmployee != null ? _teal : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      Opacity(
                        opacity: _selectedEmployee != null ? 1.0 : 0.45,
                        child: IgnorePointer(
                          ignoring: _selectedEmployee == null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Masukkan PIN untuk memulai',
                                style: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 12),
                              ),
                              const SizedBox(height: 14),

                              // PIN dot indicators
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(6, (i) {
                                  final filled = i < _enteredPin.length;
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8),
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: filled ? _teal : Colors.grey.shade300,
                                      border: Border.all(
                                        color: filled ? _teal : Colors.grey.shade400,
                                        width: 1.5,
                                      ),
                                    ),
                                  );
                                }),
                              ),

                              // Error message
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: _errorMessage != null ? 32 : 0,
                                child: _errorMessage != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                          _errorMessage!,
                                          style: GoogleFonts.poppins(
                                            color: Colors.red.shade600,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              const SizedBox(height: 20),

                              if (_isLoading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 28),
                                  child: CircularProgressIndicator(color: _teal),
                                )
                              else
                                _buildNumberPad(),
                            ],
                          ),
                        ),
                      ),
                      if (_selectedEmployee == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Pilih kasir di atas untuk mengaktifkan PIN.',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 4),
                    ],
                  ),
                ),

                // ── Dismiss layer (intercepts taps outside the dropdown) ─
                if (_dropdownOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _dropdownOpen = false),
                      child: const SizedBox.expand(),
                    ),
                  ),

                // ── Dropdown options overlay (on top, no card resize) ───
                if (_dropdownOpen)
                  Positioned(
                    top: _dropdownTopOffset,
                    left: 32,
                    right: 32,
                    child: _buildDropdownOptions(otherEmployees),
                  ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDropdownOptions(List<String> employees) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(color: _teal, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: employees.asMap().entries.map((entry) {
            final isFirst = entry.key == 0;
            final employee = entry.value;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedEmployee = employee;
                _dropdownOpen = false;
                _enteredPin = '';
                _errorMessage = null;
              }),

              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: isFirst
                      ? null
                      : Border(top: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  children: [
                    _buildAvatar(employee, isSelected: false),
                    const SizedBox(width: 12),
                    Text(
                      employee,
                      style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, {required bool isSelected}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isSelected ? _teal : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name[0],
          style: GoogleFonts.poppins(
            color: isSelected ? _yellow : Colors.black45,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        _buildPadRow(['1', '2', '3']),
        const SizedBox(height: 10),
        _buildPadRow(['4', '5', '6']),
        const SizedBox(height: 10),
        _buildPadRow(['7', '8', '9']),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 78),
            _buildDigitKey('0'),
            const SizedBox(width: 10),
            _buildDeleteKey(),
          ],
        ),
      ],
    );
  }

  Widget _buildPadRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: digits.asMap().entries.map((e) {
        return Row(
          children: [
            if (e.key > 0) const SizedBox(width: 10),
            _buildDigitKey(e.value),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildDigitKey(String digit) {
    return GestureDetector(
      onTap: () => _onDigitTap(digit),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            digit,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteKey() {
    return GestureDetector(
      onTap: _onDelete,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.backspace_outlined, size: 24, color: Colors.black54),
        ),
      ),
    );
  }
}
