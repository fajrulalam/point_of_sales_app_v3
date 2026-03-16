import 'package:flutter/material.dart';

class SidebarWidget extends StatelessWidget {
  final Color orderButtonColor;
  final Color menuButtonColor;
  final Color printButtonColor;
  final double orderButtonOffset;
  final double menuButtonOffset;
  final double printButtonOffset;
  final bool printerIsConnected;
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
  final int selfOrdersCount;

  const SidebarWidget({
    Key? key,
    required this.orderButtonColor,
    required this.menuButtonColor,
    required this.printButtonColor,
    required this.orderButtonOffset,
    required this.menuButtonOffset,
    required this.printButtonOffset,
    required this.printerIsConnected,
    required this.onOrderPressed,
    required this.onMenuPressed,
    required this.onPrintPressed,
    required this.onPrintLongPress,
    required this.onResetPressed,
    this.onRulesPressed,
    this.onInventoryPressed,
    this.onMembersPressed,
    this.onShoppingPressed,
    this.onSelfOrdersPressed,
    this.onLogoutPressed,
    this.selfOrdersCount = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Card(
        elevation: 2,
        child: Container(
          color: const Color(0xFFE8F5E9),
          child: Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildButton(
                  icon: Icons.restaurant,
                  color: orderButtonColor,
                  offset: orderButtonOffset,
                  onPressed: onOrderPressed,
                ),
                const SizedBox(height: 12),
                _buildButton(
                  icon: Icons.menu_book,
                  color: menuButtonColor,
                  offset: menuButtonOffset,
                  onPressed: onMenuPressed,
                ),
                const SizedBox(height: 12),
                _buildPrintButton(),
                const Spacer(),
                if (onInventoryPressed != null) _buildInventoryButton(),
                const SizedBox(height: 12),
                if (onShoppingPressed != null) _buildShoppingButton(),
                const SizedBox(height: 12),
                if (onSelfOrdersPressed != null) _buildSelfOrdersButton(),
                const SizedBox(height: 12),
                if (onRulesPressed != null) _buildRulesButton(),
                const SizedBox(height: 12),
                if (onMembersPressed != null) _buildMembersButton(),
                const SizedBox(height: 12),
                _buildLogoutButton(),
                const SizedBox(height: 12),
                _buildResetButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required Color color,
    required double offset,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: Offset(0, offset),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }

  Widget _buildPrintButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: printButtonColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: Offset(0, printButtonOffset),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Stack(
        children: [
          // Connection indicator
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: printerIsConnected ? Colors.green : Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Center(
            child: GestureDetector(
              onLongPress: onPrintLongPress,
              child: IconButton(
                onPressed: onPrintPressed,
                icon: const Icon(Icons.print),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'View Recommendation Rules',
        child: IconButton(
          onPressed: onRulesPressed,
          icon: Icon(Icons.auto_awesome, color: Colors.amber.shade800),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 12.0),
      child: Tooltip(
        message: 'Reset Nomor Antrian',
        child: IconButton(
          onPressed: onResetPressed,
          icon: const Icon(Icons.restart_alt),
        ),
      ),
    );
  }


  Widget _buildInventoryButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Manajemen Stok',
        child: IconButton(
          onPressed: onInventoryPressed,
          icon: Icon(Icons.inventory_2, color: Colors.blue.shade800),
        ),
      ),
    );
  }

  Widget _buildShoppingButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Shopping / Pesanan Pembelian',
        child: IconButton(
          onPressed: onShoppingPressed,
          icon: Icon(Icons.shopping_cart, color: Colors.deepOrange.shade800),
        ),
      ),
    );
  }

  Widget _buildSelfOrdersButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.teal.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Pesanan Mandiri',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onSelfOrdersPressed,
              icon: Icon(Icons.smartphone, color: Colors.teal.shade800),
            ),
            if (selfOrdersCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Center(
                    child: Text(
                      selfOrdersCount > 99 ? '99+' : '$selfOrdersCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Manajemen Member',
        child: IconButton(
          onPressed: onMembersPressed,
          icon: Icon(Icons.people, color: const Color(0xFF1B5E20)),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            blurRadius: 1,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: 'Logout',
        child: IconButton(
          onPressed: onLogoutPressed,
          icon: const Icon(Icons.logout, color: Colors.black54),
        ),
      ),
    );
  }
}
