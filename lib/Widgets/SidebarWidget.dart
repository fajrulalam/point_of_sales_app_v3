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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Card(
        elevation: 2,
        child: Container(
          color: Colors.teal.shade100,
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
                if (onRulesPressed != null) _buildRulesButton(),
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
      child: IconButton(
        onPressed: onResetPressed,
        icon: const Icon(Icons.restart_alt),
      ),
    );
  }
}
