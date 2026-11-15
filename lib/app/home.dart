import 'package:flutter/material.dart';

import 'controller.dart';
import '../features/settings/personal_center_screen.dart';
import '../features/local_media/local_media_screens.dart';
import 'theme.dart';
import '../features/search/search_screen.dart';
import '../features/search/entity_search_screen.dart';
import '../features/search/music_entity.dart';
import '../features/library/library_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/player/player_views.dart';

class MusicHome extends StatefulWidget {
  const MusicHome({super.key, required this.controller});
  final AppController controller;
  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final _songQuery = TextEditingController();
  final _playlistQuery = TextEditingController();
  int _tab = 0;
  bool _loadedLibrary = false;
  bool _loadedDiscovery = false;
  @override
  void dispose() {
    _songQuery.dispose();
    _playlistQuery.dispose();
    super.dispose();
  }

  void _search(String value) {
    FocusScope.of(context).unfocus();
    final c = widget.controller;
    if (_tab == 0) {
      if (c.entitySearch.kind == SearchKind.song) {
        c.search(value);
      } else if (c.session != null && c.entitySources.isNotEmpty) {
        c.entitySearch.search(c.session!, value);
      }
    } else if (_tab == 1 && c.session != null) {
      c.discovery.keyword = value.trim();
      c.discovery.load(c.session!);
    }
  }

  void _select(int tab) {
    final c = widget.controller;
    final session = c.session;
    if (session == null) return;
    setState(() => _tab = tab);
    if (tab == 2 && !_loadedLibrary) {
      _loadedLibrary = true;
      if (!c.offlineMode) c.refreshLibrary();
    }
    if (tab == 1 && !_loadedDiscovery && c.availableSources.isNotEmpty) {
      _loadedDiscovery = true;
      c.discovery.sources = List.of(c.availableSources);
      c.discovery.load(session, categories: !c.discovery.aggregate);
    }
  }

  void _account() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PersonalCenterScreen(controller: widget.controller),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final searchHeight = 40 * MediaQuery.textScalerOf(context).scale(14) / 14;
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
                                decoration: InputDecoration(
                                  hintText: _tab == 0
                                      ? '搜索${c.entitySearch.kind.label}'
                                      : '搜索歌单',
                                  isDense: true,
                                  hintStyle: const TextStyle(
                                    fontSize: 14,
                                    color: lxMuted,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  suffixIconConstraints:
                                      const BoxConstraints.tightFor(
                                        width: 40,
                                        height: 40,
                                      ),
                                  suffixIcon: IconButton(
                                    tooltip: '搜索',
                                    onPressed: () => _search(
                                      _tab == 0
                                          ? _songQuery.text
                                          : _playlistQuery.text,
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (_tab == 2)
                      IconButton(
                        tooltip: '本机下载',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DownloadsScreen(controller: c),
                          ),
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
              compact:
                  c.pagedCollections &&
                  ((_tab == 0 && !c.aggregate) ||
                      (_tab == 1 && !c.discovery.aggregate)),
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
