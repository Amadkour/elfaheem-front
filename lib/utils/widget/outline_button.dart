import 'package:flutter/material.dart';

class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    this.onPressed,
    required this.label,
    required this.color,
    required this.icon,
  });

  final void Function()? onPressed;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        onPressed: onPressed,
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.all(color.withAlpha(100)),
          side:WidgetStateProperty.all(BorderSide(color:color)),
        ),
      ),
    );
  }
}
