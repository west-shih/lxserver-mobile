import '../shared/compact_search.dart';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'browse_navigation.dart';
import '../features/settings/personal_center_screen.dart';
import '../features/local_media/local_media_screens.dart';
import 'theme.dart';
import '../features/search/search_screen.dart';
import '../features/search/entity_search_screen.dart';
import '../features/search/music_entity.dart';
import '../features/library/library_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/discovery/shared_playlist_sheet.dart';
import '../features/player/player_views.dart';
import '../shared/browse_route_observer.dart';

class MusicHome extends StatefulWidget {
  const MusicHome({super.key, required this.controller});
  final AppController controller;
  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> implements RouteAware {
  PageRoute<dynamic>? _route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      browseRouteObserver.unsubscribe(this);
      _route = route;
      browseRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _revalidate();
  }

  @override
  void didPush() {}
  @override
  void didPop() {}
  @override
  void didPushNext() {}

  Future<void> _revalidate() async {
    final c = widget.controller;
    final session = c.session;
    if (!mounted ||
        session == null ||
        c.offlineMode ||
        c.resumingBrowse ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (_tab == 0) {
      if (c.entitySearch.kind == SearchKind.song) {
        await c.revalidateSearch();
      } else {
        await c.entitySearch.revalidate(session);
      }
    } else if (_tab == 1) {
      await c.discovery.revalidate(session);
    }
  }

  final _songQuery = TextEditingController();
  final _playlistQuery = TextEditingController();
  int _tab = 0;
  bool _loadedLibrary = false;
  bool _loadedDiscovery = false;
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _tab = c.homeTab;
    _songQuery.text = c.songDraft;
    _playlistQuery.text = c.playlistDraft;
    _songQuery.addListener(_rememberDrafts);
    _playlistQuery.addListener(_rememberDrafts);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _select(_tab);
      if (mounted) restoreBrowseRoutes(context, c);
    });
  }

  void _rememberDrafts() => widget.controller.updateBrowseDrafts(
    _songQuery.text,
    _playlistQuery.text,
  );

  @override
  void dispose() {
    browseRouteObserver.unsubscribe(this);
    _songQuery.dispose();
    _playlistQuery.dispose();
    super.dispose();
  }

  void _search(String value) {
    FocusScope.of(context).unfocus();
    final c = widget.controller;
    if (_tab == 0) {
      if (c.entitySearch.kind == SearchKind.song) {
        c.search(value).then((_) {
          if (c.searchError == null) _revalidate();
        });
      } else if (c.session != null && c.entitySources.isNotEmpty) {
        c.entitySearch.search(c.session!, value).then((_) {
          if (c.entitySearch.error == null) _revalidate();
        });
      }
    } else if (_tab == 1 && c.session != null) {
      c.discovery.keyword = value.trim();
      c.discovery.load(c.session!).then((_) {
        if (c.discovery.error == null) _revalidate();
      });
    }
  }

  void _select(int tab) {
    final c = widget.controller;
    final session = c.session;
    if (session == null) return;
    final changedTab = _tab != tab;
    setState(() => _tab = tab);
    c.homeTab = tab;
    c.flushBrowseState();
    if (tab == 2 && !_loadedLibrary) {
      _loadedLibrary = true;
      if (!c.offlineMode && !c.library.hasSnapshot) c.refreshLibrary();
    }
    if (tab == 1 && !_loadedDiscovery && c.availableSources.isNotEmpty) {
      _loadedDiscovery = true;
      c.discovery.sources = List.of(c.availableSources);
      if (c.discovery.playlists.isEmpty &&
          c.discovery.page == 0 &&
          !c.discovery.loading &&
          !c.resumingBrowse) {
        c.discovery
            .load(session, categories: !c.discovery.aggregate)
            .then((_) => _revalidate());
      }
    }
    if (changedTab || c.savedRoutes.isEmpty) _revalidate();
  }

  void _account() => Navigator.push(
    context,
    browseRoute(PersonalCenterScreen(controller: widget.controller)),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final searchHeight = compactSearchHeight(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
              child: SizedBox(
                height: searchHeight + 8,
                child: Row(
                  children: [
                    Expanded(
                      child: _tab == 2
                          ? const Text(
                              '我的收藏',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : SizedBox(
                              height: searchHeight,
                              child: TextField(
                                key: ValueKey('top-search-$_tab'),
                                controller: _tab == 0
                                    ? _songQuery
                                    : _playlistQuery,
                                style: const TextStyle(fontSize: 14),
                                textAlignVertical: TextAlignVertical.center,
                                textInputAction: TextInputAction.search,
                                onSubmitted: _search,
                                decoration: compactSearchDecoration(
                                  hintText: _tab == 0
                                      ? '搜索${c.entitySearch.kind.label}'
                                      : '搜索歌单',
                                ),
                              ),
                            ),
                    ),
                    if (_tab == 2)
                      IconButton(
                        tooltip: '本机下载',
                        onPressed: () => Navigator.push(
                          context,
                          browseRoute(DownloadsScreen(controller: c)),
                        ),
                        icon: const Icon(Icons.downloading_rounded, size: 23),
                      ),
                    const SizedBox(width: 6),
                    if (_tab == 0)
                      PopupMenuButton<SearchKind>(
                        tooltip: '搜索类型',
                        initialValue: c.entitySearch.kind,
                        onSelected: (value) =>
                            c.selectSearchKind(value, _songQuery.text),
                        itemBuilder: (_) => SearchKind.values
                            .map(
                              (kind) => PopupMenuItem(
                                value: kind,
                                child: Row(
                                  children: [
                                    Expanded(child: Text(kind.label)),
                                    if (kind == c.entitySearch.kind)
                                      const Icon(
                                        Icons.check_rounded,
                                        color: lxGreen,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: lxGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.entitySearch.kind.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const SizedBox(
                                width: 10,
                                height: 6,
                                child: CustomPaint(
                                  painter: _SearchChevronPainter(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_tab == 1)
                      IconButton(
                        tooltip: '打开分享的歌单',
                        onPressed: () => showSharedPlaylist(context, c),
                        style: IconButton.styleFrom(
                          foregroundColor: const Color(0xFF4B5563),
                          backgroundColor: Colors.white,
                          elevation: 1,
                          shadowColor: const Color(0x1F000000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFF0F0F0)),
                          ),
                        ),
                        icon: Transform.rotate(
                          angle: -0.7853981634,
                          child: const Icon(Icons.link_rounded),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: '个人中心',
                        onPressed: _account,
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFE0F3E9),
                          child: Text(
                            c.session!.username.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: lxGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  c.entitySearch.kind == SearchKind.song
                      ? SearchScreen(controller: c)
                      : EntitySearchScreen(controller: c),
                  DiscoveryScreen(controller: c),
                  LibraryScreen(controller: c),
                ],
              ),
            ),
            MiniPlayer(
              player: c.player,
              controller: c,
              compact: c.pagedCollections,
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        selectedIndex: _tab,
        onDestinationSelected: _select,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDFF4E9),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search_rounded), label: '搜索'),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '歌单',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _SearchChevronPainter extends CustomPainter {
  const _SearchChevronPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(.8, .8)
        ..lineTo(size.width / 2, size.height - .8)
        ..lineTo(size.width - .8, .8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchChevronPainter oldDelegate) => false;
}
