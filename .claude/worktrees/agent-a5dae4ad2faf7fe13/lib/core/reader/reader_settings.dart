/// Page layout mode for the reader.
enum ReaderMode { single, double, verticalContinuous }

/// Reading direction; affects swipe direction, page slider, and spread order.
enum ReadingDirection { ltr, rtl }

/// How a page image is scaled to the viewport.
enum PageFit { width, height, screen, original }

/// Reader configuration, either the global default or a per-series override.
class ReaderSettings {
  final ReaderMode mode;
  final ReadingDirection direction;
  final PageFit fit;
  final bool doublePageCoverAlone;
  final int doublePageOffset;
  final bool tapZonesEnabled;
  final bool keepScreenOn;
  final int backgroundColor;
  final double pageGap;
  final bool upscale;
  final int brightness;
  final String colorFilter;

  const ReaderSettings({
    this.mode = ReaderMode.single,
    this.direction = ReadingDirection.ltr,
    this.fit = PageFit.screen,
    this.doublePageCoverAlone = true,
    this.doublePageOffset = 0,
    this.tapZonesEnabled = true,
    this.keepScreenOn = true,
    this.backgroundColor = 0xFF000000,
    this.pageGap = 4,
    this.upscale = false,
    this.brightness = 100,
    this.colorFilter = 'none',
  });

  ReaderSettings copyWith({
    ReaderMode? mode,
    ReadingDirection? direction,
    PageFit? fit,
    bool? doublePageCoverAlone,
    int? doublePageOffset,
    bool? tapZonesEnabled,
    bool? keepScreenOn,
    int? backgroundColor,
    double? pageGap,
    bool? upscale,
    int? brightness,
    String? colorFilter,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      direction: direction ?? this.direction,
      fit: fit ?? this.fit,
      doublePageCoverAlone: doublePageCoverAlone ?? this.doublePageCoverAlone,
      doublePageOffset: doublePageOffset ?? this.doublePageOffset,
      tapZonesEnabled: tapZonesEnabled ?? this.tapZonesEnabled,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      pageGap: pageGap ?? this.pageGap,
      upscale: upscale ?? this.upscale,
      brightness: brightness ?? this.brightness,
      colorFilter: colorFilter ?? this.colorFilter,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'direction': direction.name,
        'fit': fit.name,
        'doublePageCoverAlone': doublePageCoverAlone,
        'doublePageOffset': doublePageOffset,
        'tapZonesEnabled': tapZonesEnabled,
        'keepScreenOn': keepScreenOn,
        'backgroundColor': backgroundColor,
        'pageGap': pageGap,
        'upscale': upscale,
        'brightness': brightness,
        'colorFilter': colorFilter,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    const defaults = ReaderSettings();
    return ReaderSettings(
      mode: ReaderMode.values.byName(json['mode'] as String? ?? defaults.mode.name),
      direction: ReadingDirection.values
          .byName(json['direction'] as String? ?? defaults.direction.name),
      fit: PageFit.values.byName(json['fit'] as String? ?? defaults.fit.name),
      doublePageCoverAlone:
          json['doublePageCoverAlone'] as bool? ?? defaults.doublePageCoverAlone,
      doublePageOffset:
          json['doublePageOffset'] as int? ?? defaults.doublePageOffset,
      tapZonesEnabled: json['tapZonesEnabled'] as bool? ?? defaults.tapZonesEnabled,
      keepScreenOn: json['keepScreenOn'] as bool? ?? defaults.keepScreenOn,
      backgroundColor:
          json['backgroundColor'] as int? ?? defaults.backgroundColor,
      pageGap: (json['pageGap'] as num?)?.toDouble() ?? defaults.pageGap,
      upscale: json['upscale'] as bool? ?? defaults.upscale,
      brightness: json['brightness'] as int? ?? defaults.brightness,
      colorFilter: json['colorFilter'] as String? ?? defaults.colorFilter,
    );
  }
}
