import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/song_art.dart';
import '../../shared/card_favorite_button.dart';
import 'entity_widgets.dart';
import 'music_entity.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.controller, required this.entity});
  final AppController controller;
  final MusicEntity entity;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.library,
    builder: (context, _) {
      final saved = controller.library.isEntityFavorite(entity.favorite, false);
      return Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xffe5ece7)),
        ),
        child: InkWell(
          onTap: () => openEntity(context, controller, entity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (_, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      SongArt(
                        url: entity.image,
                        size: constraints.maxWidth,
                        borderRadius: 0,
                      ),
                      Positioned(
                        top: 3,
                        right: 2,
                        child: CardFavoriteButton(
                          tooltip: saved
                              ? '取消收藏专辑：${entity.name}'
                              : '收藏专辑：${entity.name}',
                          saved: saved,
                          onPressed: controller.library.mutating
                              ? null
                              : () => toggleEntity(context, controller, entity),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        entity.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (entity.date.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          entity.date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            color: Color(0xff97a69f),
                          ),
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entity.singer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                                color: lxMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          EntityBadge(source: entity.source),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
