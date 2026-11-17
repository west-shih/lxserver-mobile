import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxserver_mobile/core/artwork_image.dart';
import 'package:lxserver_mobile/core/browse_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Artwork replaces Dart User-Agent and preserves a non-square image aspect ratio while resizing', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final root = await Directory.systemTemp.createTemp('lx-cover-test');
    addTearDown(() => root.delete(recursive: true));
    final cache = BrowseCache(directory: () async => root);
    addTearDown(() => server.close(force: true));
    final received = Completer<List<String>?>();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final fixture = await picture.toImage(200, 100);
    final bytes = (await fixture.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    fixture.dispose();
    picture.dispose();
    server.listen((request) async {
      received.complete(request.headers[HttpHeaders.userAgentHeader]);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(bytes);
      await request.response.close();
    });
    final image = ResizeImage(
      ArtworkImage(
        'http://127.0.0.1:${server.port}/cover.png',
        headers: const {'User-Agent': 'Mozilla/5.0'},
        cache: cache,
      ),
      width: 80,
      height: 80,
      policy: ResizeImagePolicy.fit,
    );
    final decoded = Completer<ImageInfo>();
    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) => decoded.complete(info),
      onError: decoded.completeError,
    );
    stream.addListener(listener);
    addTearDown(() => stream.removeListener(listener));
    final info = await decoded.future;
    expect(await received.future, ['Mozilla/5.0']);
    expect(info.image.width, 80);
    expect(info.image.height, 40);
    info.dispose();
    await image.evict();
    final imageUrl = 'http://127.0.0.1:${server.port}/cover.png';
    await server.close(force: true);
    final offlineImage = ArtworkImage(
      imageUrl,
      headers: const {'User-Agent': 'Mozilla/5.0'},
      cache: BrowseCache(directory: () async => root),
    );
    final offline = Completer<ImageInfo>();
    final offlineStream = offlineImage.resolve(ImageConfiguration.empty);
    final offlineListener = ImageStreamListener(
      (info, _) => offline.complete(info),
      onError: offline.completeError,
    );
    offlineStream.addListener(offlineListener);
    addTearDown(() => offlineStream.removeListener(offlineListener));
    final restored = await offline.future;
    expect(restored.image.width, 200);
    expect(restored.image.height, 100);
    restored.dispose();
    await offlineImage.evict();
  });
}
