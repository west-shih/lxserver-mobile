import 'package:flutter/material.dart';

import 'controller.dart';
import '../features/search/entity_detail_screen.dart';
import '../features/search/music_entity.dart';
import '../features/library/collection_screen.dart';
import '../features/library/library_controller.dart';
import '../features/discovery/discovery_controller.dart';
import '../features/settings/personal_center_screen.dart';
import '../features/local_media/local_media_screens.dart';
import '../features/player/player_screen.dart';
import '../core/lx_api.dart';

Map<String, dynamic>? _describe(Widget page) {
  if (page is EntityDetailScreen) {
    return {
      'type': 'entity',
      'data': page.entity.raw,
      'source': page.entity.source.name,
      'artist': page.entity.artist,
    };
  }
  if (page is CollectionScreen) {
    return {
      'type': 'collection',
      'data': page.collection.snapshot(),
      'remote': page.fetchPage != null,
      'editable': page.editable,
    };
  }
  if (page is PersonalCenterScreen) return {'type': 'settings'};
  if (page is DownloadsScreen) return {'type': 'downloads'};
  if (page is CacheSettingsScreen) return {'type': 'audioSettings'};
  if (page is PlayerScreen) return {'type': 'player'};
  return null;
}

MaterialPageRoute<void> browseRoute(Widget page) => MaterialPageRoute<void>(
  settings: RouteSettings(name: 'browse', arguments: _describe(page)),
  builder: (_) => page,
);

class BrowseNavigatorObserver extends NavigatorObserver {
  BrowseNavigatorObserver(this.controller);
  final AppController controller;
  final List<Route<dynamic>> _routes = [];
  void _save() => controller.rememberRoutes([
    for (final route in _routes)
      if (route.settings.name == 'browse' &&
          route.settings.arguments is Map<String, dynamic>)
        route.settings.arguments as Map<String, dynamic>,
  ]);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    if (!route.isFirst) _save();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _save();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _save();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) _routes[index] = newRoute;
    _save();
  }
}

Widget? restoredBrowsePage(AppController c, Map value) {
  switch (value['type']) {
    case 'entity':
      final source = MusicSource.values
          .where((e) => e.name == value['source'])
          .firstOrNull;
      if (source == null || value['data'] is! Map<String, dynamic>) return null;
      return EntityDetailScreen(
        controller: c,
        entity: MusicEntity(value['data'], source, value['artist'] == true),
      );
    case 'collection':
      if (value['data'] is! Map) return null;
      var collection = MusicCollection.fromSnapshot(value['data']);
      final remote = value['remote'] == true;
      if (!remote) {
        collection =
            c.library.collections
                .where((e) => e.id == collection.id)
                .firstOrNull ??
            collection;
      }
      final source = collection.source;
      final session = c.session;
      final summary = source == null
          ? null
          : PlaylistSummary({
              'id': collection.id,
              'name': collection.name,
              'img': collection.image,
            }, source);
      return CollectionScreen(
        controller: c,
        collection: collection,
        editable: value['editable'] == true,
        fetchPage: remote && summary != null && session != null
            ? (page) => c.discovery.detail(session, summary, page)
            : null,
      );
    case 'settings':
      return PersonalCenterScreen(controller: c);
    case 'downloads':
      return DownloadsScreen(controller: c);
    case 'audioSettings':
      return CacheSettingsScreen(controller: c);
    case 'player':
      return c.player.current == null
          ? null
          : PlayerScreen(player: c.player, controller: c);
  }
  return null;
}

void restoreBrowseRoutes(BuildContext context, AppController c) {
  final saved = List<Map<String, dynamic>>.of(c.savedRoutes);
  if (saved.isEmpty) return;
  c.restoringRoutes = true;
  try {
    for (final descriptor in saved) {
      final page = restoredBrowsePage(c, descriptor);
      if (page == null) break;
      Navigator.of(context).push(browseRoute(page));
    }
  } finally {
    c.restoringRoutes = false;
  }
}
