import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WishizImage extends StatelessWidget {
  const WishizImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.placeholder,
    this.errorChild,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.measurementLabel,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Widget? placeholder;
  final Widget? errorChild;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final String? measurementLabel;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(source);
    final isRemote =
        uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');

    if (kIsWeb || isRemote) {
      return WishizNetworkImage(
        imageUrl: source,
        width: width,
        height: height,
        fit: fit,
        borderRadius: borderRadius,
        backgroundColor: backgroundColor,
        placeholder: placeholder,
        errorChild: errorChild,
        alignment: alignment,
        filterQuality: filterQuality,
        measurementLabel: measurementLabel,
      );
    }

    return _WishizLocalImage(
      source: source,
      width: width,
      height: height,
      fit: fit,
      borderRadius: borderRadius,
      backgroundColor: backgroundColor,
      placeholder: placeholder,
      errorChild: errorChild,
      alignment: alignment,
      filterQuality: filterQuality,
    );
  }
}

class WishizNetworkImage extends StatelessWidget {
  const WishizNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.placeholder,
    this.errorChild,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.fadeInDuration = const Duration(milliseconds: 180),
    this.measurementLabel,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Widget? placeholder;
  final Widget? errorChild;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;
  final String? measurementLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheSize = _resolveCacheSize(context, constraints);
        final fallback =
            errorChild ??
            _WishizImageFallback(backgroundColor: backgroundColor);
        final requestKey = '$measurementLabel:${identityHashCode(this)}';

        return ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.zero,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            filterQuality: filterQuality,
            fadeInDuration: fadeInDuration,
            memCacheWidth: cacheSize.$1,
            memCacheHeight: cacheSize.$2,
            placeholderFadeInDuration: Duration.zero,
            progressIndicatorBuilder: (context, url, progress) {
              _WishizImageMetricsTracker.onProgress(
                requestKey: requestKey,
                label: measurementLabel,
                url: url,
                progress: progress,
              );

              return placeholder ??
                  _WishizImagePlaceholder(backgroundColor: backgroundColor);
            },
            imageBuilder: (context, imageProvider) {
              _WishizImageMetricsTracker.onComplete(
                requestKey: requestKey,
                label: measurementLabel,
                url: imageUrl,
              );

              return Image(
                image: imageProvider,
                width: width,
                height: height,
                fit: fit,
                alignment: alignment,
                filterQuality: filterQuality,
              );
            },
            errorWidget: (context, url, error) => fallback,
          ),
        );
      },
    );
  }

  (int?, int?) _resolveCacheSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (kIsWeb) {
      return (null, null);
    }

    final targetWidth = _boundedDimension(width, constraints.maxWidth);
    final targetHeight = _boundedDimension(height, constraints.maxHeight);
    if (targetWidth == null && targetHeight == null) {
      return (null, null);
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return (
      _toPixelDimension(targetWidth, devicePixelRatio),
      _toPixelDimension(targetHeight, devicePixelRatio),
    );
  }

  double? _boundedDimension(double? explicit, double constrained) {
    if (explicit != null && explicit > 0) {
      return explicit;
    }
    if (!constrained.isFinite || constrained <= 0) {
      return null;
    }
    return constrained;
  }

  int? _toPixelDimension(double? logicalSize, double devicePixelRatio) {
    if (logicalSize == null) {
      return null;
    }
    final pixels = (logicalSize * devicePixelRatio).round();
    return pixels.clamp(1, 4096);
  }
}

class _WishizLocalImage extends StatelessWidget {
  const _WishizLocalImage({
    required this.source,
    this.width,
    this.height,
    required this.fit,
    this.borderRadius,
    this.backgroundColor,
    this.placeholder,
    this.errorChild,
    required this.alignment,
    required this.filterQuality,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Widget? placeholder;
  final Widget? errorChild;
  final Alignment alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.file(
        File(source),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            errorChild ??
            _WishizImageFallback(backgroundColor: backgroundColor),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            );
          }

          return placeholder ??
              _WishizImagePlaceholder(backgroundColor: backgroundColor);
        },
      ),
    );
  }
}

class _WishizImagePlaceholder extends StatelessWidget {
  const _WishizImagePlaceholder({this.backgroundColor});

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainerHigh,
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _WishizImageFallback extends StatelessWidget {
  const _WishizImageFallback({this.backgroundColor});

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surfaceContainerHigh,
      ),
      child: Center(
        child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _WishizImageMetricsTracker {
  static final Map<String, _WishizImageMetricEntry> _active =
      <String, _WishizImageMetricEntry>{};

  static int _inFlight = 0;
  static int _peakInFlight = 0;

  static void onProgress({
    required String requestKey,
    required String? label,
    required String url,
    required DownloadProgress progress,
  }) {
    if (!kDebugMode || label == null || label.isEmpty) {
      return;
    }

    final entry = _active.putIfAbsent(requestKey, () {
      _inFlight += 1;
      if (_inFlight > _peakInFlight) {
        _peakInFlight = _inFlight;
      }

      return _WishizImageMetricEntry(
        label: label,
        url: url,
        stopwatch: Stopwatch()..start(),
      );
    });

    entry.downloadedBytes = progress.downloaded.toInt();
    entry.expectedBytes = progress.totalSize?.toInt();
  }

  static void onComplete({
    required String requestKey,
    required String? label,
    required String url,
  }) {
    if (!kDebugMode || label == null || label.isEmpty) {
      return;
    }

    final entry = _active.remove(requestKey);
    if (entry == null) {
      debugPrint(
        '[WishizImage][$label] cache-hit-or-instant url=$url inFlight=$_inFlight peak=$_peakInFlight',
      );
      return;
    }

    entry.stopwatch.stop();
    _inFlight = (_inFlight - 1).clamp(0, _inFlight);
    debugPrint(
      '[WishizImage][${entry.label}] '
      'url=${entry.url} '
      'durationMs=${entry.stopwatch.elapsedMilliseconds} '
      'downloaded=${_formatBytes(entry.downloadedBytes)} '
      'expected=${_formatBytes(entry.expectedBytes)} '
      'inFlight=$_inFlight '
      'peak=$_peakInFlight',
    );
  }

  static String _formatBytes(int? bytes) {
    if (bytes == null) {
      return 'unknown';
    }
    if (bytes < 1024) {
      return '${bytes}B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }
}

class _WishizImageMetricEntry {
  _WishizImageMetricEntry({
    required this.label,
    required this.url,
    required this.stopwatch,
  });

  final String label;
  final String url;
  final Stopwatch stopwatch;
  int? downloadedBytes;
  int? expectedBytes;
}
