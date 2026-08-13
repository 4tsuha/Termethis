import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class RdpVulkanView extends StatefulWidget {
  const RdpVulkanView({
    required this.sessionId,
    this.onRendererReady,
    this.onRendererError,
    super.key,
  });

  final int sessionId;
  final ValueChanged<String>? onRendererReady;
  final ValueChanged<String>? onRendererError;

  @override
  State<RdpVulkanView> createState() => _RdpVulkanViewState();
}

class _RdpVulkanViewState extends State<RdpVulkanView> {
  static const _viewType = 'jp.yts.termethis/rdp_vulkan';

  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Vulkan RDP描画はAndroidでのみ利用できます。',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: {'sessionId': widget.sessionId},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener((viewId) {
          params.onPlatformViewCreated(viewId);
          _onPlatformViewCreated(viewId);
        });
        controller.create();
        return controller;
      },
    );
  }

  Future<void> _onPlatformViewCreated(int viewId) async {
    final channel = MethodChannel('$_viewType/$viewId');
    _channel = channel;
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'initialize',
      );
      if (!mounted) return;
      widget.onRendererReady?.call(
        result?['renderer'] as String? ?? 'native Vulkan Surface',
      );
    } catch (error) {
      if (mounted) widget.onRendererError?.call('$error');
    }
  }
}
