import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

// ── Bitepoint palette ──────────────────────────────────────────────
const Color kDarkTeal = Color(0xFF069494);
const Color kWarmYellow = Color(0xFFF5C518);
const Color kSidebarBg = Color(0xFFFAFAFA);
const Color kOffWhite = Color(0xFFF5F5F0);

class SidebarWidget extends StatefulWidget {
  final bool printerIsConnected;
  final int liveTabsCount;
  final String activeRoute;

  // Navigation callbacks
  final VoidCallback onOrderPressed;
  final VoidCallback onMenuPressed;
  final VoidCallback onPrintPressed;
  final VoidCallback onPrintLongPress;
  final VoidCallback onResetPressed;
  final VoidCallback? onRulesPressed;
  final VoidCallback? onInventoryPressed;
  final VoidCallback? onMembersPressed;
  final VoidCallback? onShoppingPressed;
  final VoidCallback? onSelfOrdersPressed;
  final VoidCallback? onLogoutPressed;
  final VoidCallback? onFinancialReportPressed;
  final VoidCallback? onTestingModeToggled;

  // New controlled state props
  final bool isExpanded;
  final bool isMinimized;
  final VoidCallback onExpandToggled;
  final VoidCallback onMinimizeToggled;

  const SidebarWidget({
    Key? key,
    required this.printerIsConnected,
    required this.liveTabsCount,
    required this.activeRoute,
    required this.onOrderPressed,
    required this.onMenuPressed,
    required this.onPrintPressed,
    required this.onPrintLongPress,
    required this.onResetPressed,
    required this.isExpanded,
    required this.isMinimized,
    required this.onExpandToggled,
    required this.onMinimizeToggled,
    this.onRulesPressed,
    this.onInventoryPressed,
    this.onMembersPressed,
    this.onShoppingPressed,
    this.onSelfOrdersPressed,
    this.onLogoutPressed,
    this.onFinancialReportPressed,
    this.onTestingModeToggled,
  }) : super(key: key);

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  static const double _expandedWidth = 220;
  static const Duration _animDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final double sidebarWidth = widget.isMinimized ? 0 : _expandedWidth;

    return AnimatedContainer(
      duration: _animDuration,
      curve: Curves.easeInOut,
      width: sidebarWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: kSidebarBg,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: widget.isMinimized
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(2, 0),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool showLabels = constraints.maxWidth > 50;
          final bool isFullyCollapsed = constraints.maxWidth < 10;

          return SafeArea(
            child: Opacity(
              opacity: isFullyCollapsed ? 0 : 1,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _buildHeader(showLabels),
                  const SizedBox(height: 24),
                  
                  // Nav Items
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _navItem(
                            icon: Icons.dashboard_rounded,
                            label: 'Dashboard',
                            routeKey: 'pos_order',
                            onTap: widget.onOrderPressed,
                            showLabels: showLabels,
                          ),
                          _navItem(
                            icon: Icons.menu_book_rounded,
                            label: 'Menu',
                            routeKey: 'pos_menu',
                            onTap: widget.onMenuPressed,
                            showLabels: showLabels,
                          ),
                          _navItem(
                            icon: Icons.print_rounded,
                            label: 'Printer',
                            routeKey: 'printer',
                            onTap: widget.onPrintPressed,
                            onLongPress: widget.onPrintLongPress,
                            trailing: _printerDot(),
                            showLabels: showLabels,
                          ),
                          if (widget.onSelfOrdersPressed != null)
                            _navItem(
                              icon: Icons.smartphone_rounded,
                              label: 'Live Tabs',
                              routeKey: 'selforders',
                              onTap: widget.onSelfOrdersPressed!,
                              badge: widget.liveTabsCount,
                              showLabels: showLabels,
                            ),

                          const SizedBox(height: 8),
                          _divider(),
                          const SizedBox(height: 8),

                          if (widget.onInventoryPressed != null)
                            _navItem(
                              icon: Icons.inventory_2_rounded,
                              label: 'Stock',
                              routeKey: 'inventory',
                              onTap: widget.onInventoryPressed!,
                              showLabels: showLabels,
                            ),
                          if (widget.onShoppingPressed != null)
                            _navItem(
                              icon: Icons.shopping_cart_rounded,
                              label: 'Shopping',
                              routeKey: 'shopping',
                              onTap: widget.onShoppingPressed!,
                              showLabels: showLabels,
                            ),
                          if (widget.onMembersPressed != null)
                            _navItem(
                              icon: Icons.people_rounded,
                              label: 'Marketing',
                              routeKey: 'members',
                              onTap: widget.onMembersPressed!,
                              showLabels: showLabels,
                            ),
                          if (widget.onFinancialReportPressed != null)
                            _navItem(
                              icon: Icons.assessment_rounded,
                              label: 'Accounting',
                              routeKey: 'financial',
                              onTap: widget.onFinancialReportPressed!,
                              showLabels: showLabels,
                            ),
                        ],
                      ),
                    ),
                  ),

                  _navItem(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reset Queue',
                    routeKey: '__reset__',
                    onTap: widget.onResetPressed,
                    iconColor: Colors.redAccent,
                    showLabels: showLabels,
                  ),

                  _divider(),
                  _buildTestingToggle(showLabels),
                  _buildUserProfile(showLabels),
                  const SizedBox(height: 4),

                  _navItem(
                    icon: Icons.logout_rounded,
                    label: 'Logout',
                    routeKey: '__logout__',
                    onTap: widget.onLogoutPressed ?? () {},
                    iconColor: Colors.redAccent.shade200,
                    showLabels: showLabels,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool showLabels) {
    final brandIcon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: kDarkTeal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.restaurant_menu_rounded,
        color: kWarmYellow,
        size: 22,
      ),
    );

    final toggleButton = InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: widget.onMinimizeToggled,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: kDarkTeal.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.chevron_left_rounded,
          color: kDarkTeal,
          size: 20,
        ),
      ),
    );

    if (!showLabels) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          brandIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Canteen 375',
              style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kDarkTeal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          toggleButton,
        ],
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required String routeKey,
    required VoidCallback onTap,
    required bool showLabels,
    VoidCallback? onLongPress,
    int badge = 0,
    Widget? trailing,
    Color? iconColor,
  }) {
    final bool isActive = _resolveActive(routeKey);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: _animDuration,
            curve: Curves.easeInOut,
            padding: EdgeInsets.symmetric(
              horizontal: showLabels ? 14 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isActive ? kWarmYellow : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: iconColor ?? (isActive ? kDarkTeal : kDarkTeal.withOpacity(0.55)),
                    ),
                    if (badge > 0)
                      Positioned(
                        top: -6,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Center(
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (trailing != null) ...[const SizedBox(width: 4), trailing],
                if (showLabels) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? kDarkTeal : kDarkTeal.withOpacity(0.65),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        height: 1,
        color: kDarkTeal.withOpacity(0.06),
      );

  Widget _printerDot() => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.printerIsConnected ? Colors.green : Colors.red,
          shape: BoxShape.circle,
        ),
      );

  Widget _buildTestingToggle(bool showLabels) {
    if (!showLabels) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: Col.testingMode,
      builder: (context, isTesting, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTestingModeToggled,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isTesting ? Colors.orange.shade50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isTesting
                      ? Border.all(color: Colors.orange.shade300, width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.science_rounded,
                      size: 20,
                      color: isTesting ? Colors.orange.shade700 : kDarkTeal.withOpacity(0.55),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Testing',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isTesting ? Colors.orange.shade700 : kDarkTeal.withOpacity(0.65),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      width: 40,
                      child: Switch(
                        value: isTesting,
                        onChanged: (_) => widget.onTestingModeToggled?.call(),
                        activeColor: Colors.orange.shade700,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserProfile(bool showLabels) {
    if (!showLabels) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kDarkTeal.withOpacity(0.1),
            child: const Icon(Icons.person_outline, size: 18, color: kDarkTeal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cashier',
                  style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w600, color: kDarkTeal),
                ),
                Text(
                  'Admin Mode',
                  style: GoogleFonts.montserrat(fontSize: 10, color: kDarkTeal.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _resolveActive(String routeKey) {
    if (widget.activeRoute == routeKey) return true;
    if (widget.activeRoute == 'pos_order' && routeKey == 'pos_order') return true;
    return false;
  }
}
