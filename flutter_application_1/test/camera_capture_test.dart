import 'dart:async';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/media/camera_capture_screen.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestCamera extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final events = <String>[];
  final audio = <bool>[];
  final resolutions = <ResolutionPreset?>[];
  int next = 0;
  int open = 0;
  int maximumOpen = 0;
  final activeIds = <int>{};
  bool deny = false;
  bool failStop = false;
  bool failFlash = false;
  bool failSwitch = false;
  final persistent = <bool>[];
  @override
  Future<void> setDescriptionWhileRecording(
    CameraDescription description,
  ) async {
    if (failSwitch) throw CameraException('unsupported', 'No switch');
    events.add('switch:${description.name}');
  }

  final flashModes = <FlashMode>[];
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (failFlash) throw CameraException('unsupported', 'No flash');
    flashModes.add(mode);
  }

  Completer<void>? initializing;
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    if (deny) throw CameraException('CameraAccessDenied', 'denied');
    audio.add(settings.enableAudio);
    resolutions.add(settings.resolutionPreset);
    open++;
    if (open > maximumOpen) maximumOpen = open;
    events.add('open:${description.name}');
    activeIds.add(++next);
    return next;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializing?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((e) => e.cameraId == cameraId);
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Widget buildPreview(int cameraId) => const SizedBox(width: 640, height: 480);
  @override
  Future<void> dispose(int cameraId) async {
    if (!activeIds.remove(cameraId)) return;
    open--;
    events.add('close');
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile('photo.jpg');
  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    events.add('record');
    persistent.add(options.enablePersistentRecording);
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    events.add('stop');
    if (failStop) throw CameraException('disconnected', 'lost camera');
    return XFile('video.mp4');
  }
}

void main() {
  late TestCamera camera;
  late CameraPlatform previous;
  final lightCalls = <bool>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = CameraPlatform.instance;
    camera = TestCamera();
    CameraPlatform.instance = camera;
    lightCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app/camera_light'), (
          call,
        ) async {
          lightCalls.add((call.arguments as Map)['enabled'] as bool);
          return null;
        });
  });
  tearDown(() {
    CameraPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app/camera_light'),
          null,
        );
  });

  testWidgets(
    'Front video uses screen light and switches lens without stopping recording',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CameraCaptureScreen(video: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kamerayı değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Flaşı aç'));
      await tester.pumpAndSettle();
      expect(lightCalls.last, true);
      expect(camera.flashModes, isNot(contains(FlashMode.torch)));
      await tester.tap(find.text('Kayda başla'));
      await tester.pumpAndSettle();
      expect(camera.persistent.last, true);
      await tester.tap(find.byTooltip('Kamerayı değiştir'));
      await tester.pumpAndSettle();
      expect(camera.events.last, 'switch:back');
      expect(lightCalls.last, false);
      expect(camera.events, isNot(contains('stop')));
      expect(camera.maximumOpen, 1);
      expect(find.text('Kaydı bitir'), findsOneWidget);
      camera.failSwitch = true;
      await tester.tap(find.byTooltip('Kamerayı değiştir'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Bu cihaz kayıt sırasında kamera değiştiremedi'),
        findsOneWidget,
      );
      expect(camera.open, 1);
      expect(camera.events, isNot(contains('stop')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Front photo flashes the screen temporarily and restores brightness',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<XFile>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CameraCaptureScreen(video: false),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kamerayı değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Flaşı aç'));
      await tester.pumpAndSettle();
      expect(lightCalls, isEmpty);
      await tester.tap(find.text('Fotoğraf çek').last);
      await tester.pump();
      expect(lightCalls.last, true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(lightCalls, [true, false]);
      expect(camera.open, 0);
    },
  );

  for (final video in [false, true]) {
    testWidgets(
      'Flash mode works for ${video ? 'video' : 'photo'} without reopening camera',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: CameraCaptureScreen(video: video)),
        );
        await tester.pumpAndSettle();
        expect(camera.flashModes.last, FlashMode.off);
        await tester.tap(find.byTooltip('Flaşı aç'));
        await tester.pumpAndSettle();
        expect(
          camera.flashModes.last,
          video ? FlashMode.torch : FlashMode.always,
        );
        if (video) {
          await tester.tap(find.text('Kayda başla'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Flaşı kapat'));
        await tester.pumpAndSettle();
        expect(camera.flashModes.last, FlashMode.off);
        camera.failFlash = true;
        await tester.tap(find.byTooltip('Flaşı aç'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Flaşsız çekime'), findsOneWidget);
        expect(camera.open, 1);
        expect(camera.maximumOpen, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('Camera releases before lens switch, pause, resume and exit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CameraCaptureScreen(video: false)),
    );
    await tester.pumpAndSettle();
    expect(camera.open, 1);
    expect(camera.audio, [false]);
    expect(camera.resolutions.first, ResolutionPreset.veryHigh);
    await tester.tap(find.byTooltip('Kamerayı değiştir'));
    await tester.pumpAndSettle();
    expect(camera.events.take(3), ['open:back', 'close', 'open:front']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump();
    expect(camera.open, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.open, 1);
    expect(camera.maximumOpen, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(camera.open, 0);
  });

  testWidgets(
    'Rapid background/resume during initialization keeps one session',
    (tester) async {
      camera.initializing = Completer<void>();
      await tester.pumpWidget(
        const MaterialApp(home: CameraCaptureScreen(video: false)),
      );
      await tester.pump();
      expect(camera.open, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      camera.initializing!.complete();
      await tester.pumpAndSettle();
      expect(camera.open, 1);
      expect(camera.maximumOpen, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(camera.open, 0);
    },
  );

  testWidgets('Camera disconnect releases resource and allows retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CameraCaptureScreen(video: false)),
    );
    await tester.pumpAndSettle();
    camera.errors.add(CameraErrorEvent(camera.next, 'Camera busy'));
    await tester.pumpAndSettle();
    expect(camera.open, 0);
    expect(find.textContaining('Kamera kullanılamıyor'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(camera.open, 1);
    expect(camera.maximumOpen, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Video records and releases camera before returning captured file',
    (tester) async {
      XFile? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<XFile>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CameraCaptureScreen(video: true),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayda başla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydı bitir'));
      await tester.pumpAndSettle();
      expect(result?.path, 'video.mp4');
      expect(camera.audio, [true]);
      expect(camera.events, ['open:back', 'record', 'stop', 'close']);
      expect(camera.open, 0);
    },
  );

  testWidgets(
    'Permission denial offers a retry without opening a second session',
    (tester) async {
      camera.deny = true;
      await tester.pumpWidget(
        const MaterialApp(home: CameraCaptureScreen(video: false)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Kamera izni verilmedi'), findsOneWidget);
      expect(camera.open, 0);
      camera.deny = false;
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(camera.open, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Transient focus loss preserves recording; full background saves partial clip',
    (tester) async {
      XFile? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await Navigator.push<XFile>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CameraCaptureScreen(video: true),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayda başla'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(camera.events, ['open:back', 'record']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.open, 1);
      expect(camera.events, ['open:back', 'record']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.events, ['open:back', 'record', 'stop', 'close']);
      expect(find.text('Çekilmiş kısmı kullan'), findsOneWidget);
      await tester.tap(find.text('Çekilmiş kısmı kullan'));
      await tester.pumpAndSettle();
      expect(result?.path, 'video.mp4');
    },
  );

  testWidgets(
    'Camera interruption attempts to save, and reports if OS cannot finalize',
    (tester) async {
      camera.failStop = true;
      await tester.pumpWidget(
        const MaterialApp(home: CameraCaptureScreen(video: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kayda başla'));
      await tester.pumpAndSettle();
      camera.errors.add(CameraErrorEvent(camera.next, 'camera taken'));
      await tester.pumpAndSettle();
      expect(camera.events, containsAllInOrder(['record', 'stop', 'close']));
      expect(find.text('Çekilmiş kısmı kullan'), findsNothing);
      expect(find.text('Tekrar dene'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final entry in {
    'Fotoğraf çek': (false, false),
    'Video çek': (true, false),
    'Galeriden fotoğraf seç': (false, true),
    'Galeriden video seç': (true, true),
  }.entries) {
    testWidgets(
      '${entry.key} hides keyboard and cancellation preserves draft',
      (tester) async {
        (bool, bool)? selected;
        final pick = Completer<XFile?>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ChatComposer(
                onSend: (_, _) async {},
                pickMedia: (video, gallery) {
                  selected = (video, gallery);
                  return pick.future;
                },
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'Draft');
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.tap(find.byTooltip('Fotoğraf, video veya konum'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(selected, entry.value);
        expect(tester.testTextInput.isVisible, isFalse);
        pick.complete(null);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Draft',
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
      },
    );
  }
}
