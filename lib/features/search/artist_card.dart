import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/song_art.dart';
import 'entity_widgets.dart';
import 'music_entity.dart';

class ArtistCard extends StatelessWidget {
  const ArtistCard({super.key, required this.controller, required this.entity});
  final AppController controller;
  final MusicEntity entity;
  static double portraitSize(double width) => (width - 32).clamp(72.0, 180.0);
  static double extent(double width, double scale) =>
      portraitSize(width) + 48 + 67 * scale;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.library,
    builder: (context, _) {
      final saved = controller.library.isEntityFavorite(entity.favorite, true);
      final scaler = MediaQuery.textScalerOf(context);
      return LayoutBuilder(
        builder: (context, box) {
          final size = portraitSize(box.maxWidth);
          return Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: const Color(0x15172b28),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: Color(0xffe6eeea)),
            ),
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff0faf5), Colors.white],
                  stops: [0, .6],
                ),
              ),
              child: InkWell(
                onTap: () => openEntity(context, controller, entity),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: size,
                              height: size,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: saved
                                    ? const Color(0xff94e2c8)
                                    : const Color(0xffdbe9e2),
                              ),
                              child: ClipOval(
                                child: SongArt(
                                  url: entity.image,
                                  size: size - 6,
                                  borderRadius: 0,
                                  placeholderIcon: Icons.person_outline_rounded,
                                  placeholderColor: Colors.white,
                                  placeholderBackground: const Color(
                                    0xffe2e6e4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: scaler.scale(27.3),
                            child: Center(
                              child: Text(
                                entity.name,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: scaler.scale(16.8),
                            child: Text(
                              entity.alias,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: lxMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: scaler.scale(22),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                EntityBadge(source: entity.source),
                                if (entity.number('albumSize') != null) ...[
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfff6f8f7),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xffe8edea),
                                        ),
                                      ),
                                      child: Text(
                                        '${entity.number('albumSize')} 专辑',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          height: 1.3,
                                          color: Color(0xff61726a),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        tooltip: saved
                            ? '取消收藏歌手：${entity.name}'
                            : '收藏歌手：${entity.name}',
                        isSelected: saved,
                        onPressed: controller.library.mutating
                            ? null
                            : () => toggleEntity(context, controller, entity),
                        alignment: Alignment.topRight,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          fixedSize: const Size(40, 40),
                          minimumSize: const Size(40, 40),
                        ),
                        icon: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x66172922),
                          ),
                          child: Icon(
                            saved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
