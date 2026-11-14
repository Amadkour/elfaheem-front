// lib/utils/widget/search_text_field.dart
//
// The older list search bar (favourites, course lists, a course's students): the kit's search well
// (appFieldDecoration with the search icon, 48 high, the 2 px ring on focus) with the page gutter around it. It is a
// plain TextField with the search action, so Ctrl+K and "/" find it (app_keyboard.dart). New screens use
// AppSearchField (debounce, clear, Esc).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../config/app_config.dart';

class MySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final void Function(String)? onChanged;

  const MySearchBar(
      {super.key, required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
      child: TextField(
        controller: controller,
        textDirection: pageDirection,
        textInputAction: TextInputAction.search,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(context, hint: hint.tr, icon: Icons.search_rounded)
            .copyWith(hintTextDirection: pageDirection),
        onChanged: onChanged,
      ),
    );
  }
}
