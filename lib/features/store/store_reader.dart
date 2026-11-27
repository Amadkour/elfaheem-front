// lib/features/store/store_reader.dart — the in-app reader of a bought PDF on a phone or a desktop (D-1333).
//
// The kept copy is decrypted into memory only (StoreVault.read) and drawn by pdfrx; while the page is open the
// window is protected through ScreenSecurity.protect(owner) / release(owner) (D-083: never the plugin itself, so
// another protected screen keeps its protection and a screen share keeps this area black).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:pdfrx/pdfrx.dart';

class StoreReaderPage extends StatefulWidget {
  const StoreReaderPage({super.key, required this.itemId, required this.title, required this.load});

  final int itemId;
  final String title;

  /// The plain bytes (StoreVault.instance.read).
  final Future<Uint8List> Function() load;

  @override
  State<StoreReaderPage> createState() => _StoreReaderPageState();
}

class _StoreReaderPageState extends State<StoreReaderPage> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.instance.protect(this);
    _open();
  }

  @override
  void dispose() {
    ScreenSecurity.instance.release(this);
    _bytes = null;
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final b = await widget.load();
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('تعذّر فتح الملف. نزّله من جديد من «مكتبتي».', 'The file could not be opened. Download it again from My Library.'));
      }
    }
  }

  int _page = 1, _pages = 0;

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    return SdArea(area: AppArea.store, child: BasePage(
      appBar: ScreenAppBar(title: widget.title, compact: true),
      child: SafeArea(
        child: _error != null
            ? AppErrorState(message: _error, onRetry: _open)
            : b == null
                ? const AppListSkeleton(items: 4, withAvatar: false)
                // Stu2Store `screen=reader`: the page on a dark reading surface, "صفحة ١٢ من ٨٦" and the read share
                // in a slim bar under it
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: PdfViewer.data(
                        b,
                        sourceName: 'store-${widget.itemId}',
                        params: PdfViewerParams(
                          backgroundColor: context.colors.kit.deep,
                          onViewerReady: (doc, _) {
                            if (mounted) setState(() => _pages = doc.pages.length);
                          },
                          onPageChanged: (n) {
                            if (mounted && n != null) setState(() => _page = n);
                          },
                        ),
                      ),
                    ),
                    if (_pages > 0) StoreReaderBar(page: _page, pages: _pages),
                  ]),
      ),
    ));
  }
}

/// The reader's foot: "صفحة ١٢ من ٨٦", the read share drawn as a bar in the area's gradient, and the percent.
class StoreReaderBar extends StatelessWidget {
  const StoreReaderBar({super.key, required this.page, required this.pages});

  final int page, pages;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = pages <= 0 ? 0.0 : (page / pages).clamp(0.0, 1.0);
    return ColoredBox(
      color: c.kit.deep,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Row(children: [
            Text(appDigits('sd_reader_page'.tr.replaceAll('{n}', '$page').replaceAll('{of}', '$pages')),
                style: AppType.label(context).copyWith(color: c.onHero)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: AppProgressBar(value: share, max: 1)),
            const SizedBox(width: AppSpace.sm),
            Text(appDigits('${(share * 100).round()}%'), style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
          ]),
        ),
      ),
    );
  }
}
