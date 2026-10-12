import 'package:flutter/material.dart';

import '../../../config/app_config.dart';

class PrivateFlag extends StatelessWidget {
  const PrivateFlag({super.key,  this.label});
  final String? label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE24B4A).withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 3,),
           Text(
           label?? 'private'.tr,
            maxLines: 1,
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontFamily: 'bahji'
            ),
          )
        ],
      ),
    );
  }
}
