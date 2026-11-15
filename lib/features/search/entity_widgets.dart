import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/lx_api.dart';
import '../../shared/music_badge.dart';
import '../../shared/app_modal.dart';
import 'music_entity.dart';
import 'entity_detail_screen.dart';
import 'album_card.dart';
import 'artist_card.dart';

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
  if (!desired) {
    final confirmed = await showAppDialog<bool>(
      context: context,
      dangerous: true,
      builder: (dialog) => AlertDialog(
        title: Text(entity.artist ? '取消收藏歌手？' : '取消收藏专辑？'),
        content: Text('确定取消收藏「${entity.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留收藏'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || c.session != session) return;
  }
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
                ? width + 24 + 57 * scale + (hasDates ? 16 * scale : 0)
                : ArtistCard.extent(width, scale),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final entity = items[index];
            if (!entity.artist) {
              return AlbumCard(controller: controller, entity: entity);
            }
            return ArtistCard(controller: controller, entity: entity);
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
