// lib/design/master_detail/entity_detail_page.dart — a student / course / teacher / category on a page of its own
// (route `entity.view`, `/view/:kind/:id`, D-290): refresh-safe, every role (the server decides what each one sees).
//
// The same panel as the lists' (EntityPanelMode.page), centred at a readable width, with its own trail: a link on
// the page drills in and the breadcrumbs walk back. Opened by EntityNavigator.openFullPage, a URL, a notification.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';

import '../app_tokens.dart';
import 'entity_detail_view.dart';
import 'entity_panel.dart';
import 'entity_panel_controller.dart';

class EntityDetailPage extends StatefulWidget {
  const EntityDetailPage({super.key, required this.entity, this.from, this.actions});

  /// What to show (a ref with a name draws it at once).
  final EntityRef entity;

  /// What it was opened from (`?from=`): the start of the trail, so a student keeps that course in focus.
  final EntityRef? from;
  final EntityActionsBuilder? actions;

  /// The page's widest content.
  static const double maxWidth = 920;

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage> {
  late final _controller = EntityPanelController();

  @override
  void initState() {
    super.initState();
    _openEntity();
    _controller.addListener(_closed);
  }

  void _openEntity() {
    final from = widget.from;
    if (from == null) {
      _controller.open(widget.entity);
    } else {
      _controller
        ..open(from)
        ..push(widget.entity);
    }
  }

  /// The entity went away (a student deleted from here): the page leaves with it.
  void _closed() {
    if (_controller.isOpen || !mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed(AppRoutes.adminHome.path);
    }
  }

  @override
  void didUpdateWidget(covariant EntityDetailPage old) {
    super.didUpdateWidget(old);
    if (old.entity != widget.entity || old.from != widget.from) _openEntity();
  }

  @override
  void dispose() {
    _controller.removeListener(_closed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: EntityDetailPage.maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.cardBg, boxShadow: AppElevation.of(context, 1)),
              child: EntityPanel(controller: _controller, mode: EntityPanelMode.page, actions: widget.actions),
            ),
          ),
        ),
      ),
    );
  }
}
