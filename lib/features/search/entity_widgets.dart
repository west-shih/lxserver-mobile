import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../core/lx_api.dart';
import '../../shared/music_badge.dart';
import '../../shared/song_art.dart';
import 'music_entity.dart';
import 'entity_detail_screen.dart';
import 'album_card.dart';

void openEntity(BuildContext context, AppController c, MusicEntity entity) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => EntityDetailScreen(controller: c, entity: entity),
    ),
  );
}

Future<void> toggleEntity(
  BuildContext context,
  AppController c,
  MusicEntity entity,
) async {
  final session = c.session;
  if (session == null) return;
  final desired = !c.library.isEntityFavorite(entity.favorite, entity.artist);
  try {
    await c.library.setEntityFavorite(
      session,
      entity.favorite,
      entity.artist,
      desired,
    );
    if (context.mounted && c.session == session) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(desired ? '已收藏' : '已取消收藏')));
    }
  } catch (e) {
    if (context.mounted && c.session == session) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiFailure ? '${e.message}；保存状态请刷新核对' : '收藏操作失败，请刷新核对',
          ),
        ),
      );
    }
  }
}

class EntityGrid extends StatelessWidget {
  const EntityGrid({super.key, required this.controller, required this.items});
  final AppController controller;
  final List<MusicEntity> items;
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (constraints.crossAxisExtent / (160 * scale))
          .floor()
          .clamp(1, 4);
      final width =
          (constraints.crossAxisExtent - 28 - 12 * (columns - 1)) / columns;
      final albumGrid = items.firstOrNull?.artist == false;
      final hasDates = items.any((e) => e.date.isNotEmpty);
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: albumGrid
                ? width + 28 + 57 * scale + (hasDates ? 20 * scale : 0)
                : 135 + 115 * scale,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final entity = items[index];
            if (!entity.artist) {
              return AlbumCard(controller: controller, entity: entity);
            }
            final saved = controller.library.isEntityFavorite(
              entity.favorite,
              entity.artist,
            );
            return Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
                side: const BorderSide(color: Color(0xffe5ece7)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openEntity(context, controller, entity),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: entity.artist
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Center(
                              child: entity.artist
                                  ? ClipOval(
                                      child: SongArt(
                                        url: entity.image,
                                        size: 96,
                                      ),
                                    )
                                  : SongArt(url: entity.image, size: 138),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            entity.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if ((entity.artist ? entity.alias : entity.singer)
                              .isNotEmpty)
                            Text(
                              entity.artist ? entity.alias : entity.singer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: lxMuted,
                              ),
                            ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              EntityBadge(source: entity.source),
                              if (entity.artist &&
                                  entity.number('albumSize') != null)
                                Text(
                                  '${entity.number('albumSize')} 专辑',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: lxMuted,
                                  ),
                                ),
                            ],
                          ),
                          if (!entity.artist && entity.date.isNotEmpty)
                            Text(
                              entity.date,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 10,
                                color: lxMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: saved ? '取消收藏' : '收藏',
                        onPressed: controller.library.mutating
                            ? null
                            : () => toggleEntity(context, controller, entity),
                        icon: Icon(
                          saved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: saved ? const Color(0xffed5277) : lxMuted,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class EntityBadge extends StatelessWidget {
  const EntityBadge({super.key, required this.source});
  final MusicSource source;
  @override
  Widget build(BuildContext context) =>
      MusicBadge(source.label, tone: MusicBadge.source(source));
}
