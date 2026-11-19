import 'media_exporter.dart';
import 'native_bridge.dart';

/// Aggregated file count and estimated total size for a [MediaSource].
class MediaSourceStats {
  final int fileCount;
  final int totalBytes;

  const MediaSourceStats({
    this.fileCount = 0,
    this.totalBytes = 0,
  });

  factory MediaSourceStats.fromMap(Map<Object?, Object?> map) => MediaSourceStats(
        fileCount: (map['count'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      );

  MediaSourceStats operator +(MediaSourceStats other) => MediaSourceStats(
        fileCount: fileCount + other.fileCount,
        totalBytes: totalBytes + other.totalBytes,
      );
}

/// Extensible hierarchical contract for backup media sources and sub-items
/// (e.g., Camera -> Images/Videos, WhatsApp -> Received/Sent -> Images/Videos/Audios,
/// Screenshots, Recorded Audios, and future sources).
abstract class MediaSource {
  /// Stable unique identifier (persisted for leaf nodes), e.g. `"camera.images"`.
  String get id;

  /// Human-readable label displayed in the UI.
  String get displayName;

  /// Short folder/description hint shown beneath the title.
  String get subtitle;

  /// Remote folder path under `{base_path}/{device_name}/`, e.g. `"whatsapp/sent/videos"`.
  String get destinationSlug;

  /// Nested sub-sources (empty for leaf sources).
  List<MediaSource> get children;

  bool get isGroup => children.isNotEmpty;

  /// All leaf source IDs represented by this node (itself if leaf, else all descendant leaves).
  Set<String> get leafIds {
    if (!isGroup) return {id};
    final out = <String>{};
    for (final child in children) {
      out.addAll(child.leafIds);
    }
    return out;
  }

  /// Sums file count and byte size across all descendant leaves.
  MediaSourceStats aggregateStats(Map<String, MediaSourceStats> leafStats) {
    var total = const MediaSourceStats();
    for (final leaf in leafIds) {
      final stat = leafStats[leaf];
      if (stat != null) total = total + stat;
    }
    return total;
  }

  /// Tri-state selection value: `true` if all leaves enabled, `false` if none, `null` if partial.
  bool? selectionState(Set<String> enabledLeafIds) {
    final leaves = leafIds;
    final selectedCount = leaves.where(enabledLeafIds.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == leaves.length) return true;
    return null;
  }

  /// Discovers items belonging to this source (no thumbnails/previews).
  Future<List<BackupItem>> discoverItems({int? perSourceLimit});
}

/// Concrete leaf or group media source backed by [NativeBackupBridge].
class BridgeMediaSource extends MediaSource {
  final NativeBackupBridge _bridge;
  @override
  final String id;
  @override
  final String displayName;
  @override
  final String subtitle;
  @override
  final String destinationSlug;
  @override
  final List<MediaSource> children;

  BridgeMediaSource({
    required this._bridge,
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.destinationSlug,
    this.children = const [],
  });

  @override
  Future<List<BackupItem>> discoverItems({int? perSourceLimit}) => _bridge.discoverMedia(
        enabledSourceIds: leafIds,
        perSourceLimit: perSourceLimit,
      );
}

/// All registered leaf source IDs enabled by default.
const Set<String> defaultEnabledMediaSourceIds = {
  'camera.images',
  'camera.videos',
  'screenshots',
  'whatsapp.received.images',
  'whatsapp.received.videos',
  'whatsapp.received.audios',
  'whatsapp.sent.images',
  'whatsapp.sent.videos',
  'whatsapp.sent.audios',
  'recordings',
};

/// Default hierarchical registry of supported [MediaSource] trees.
List<MediaSource> defaultMediaSources(NativeBackupBridge bridge) => [
      BridgeMediaSource(
        bridge: bridge,
        id: 'camera',
        displayName: 'Camera',
        subtitle: 'DCIM/Camera',
        destinationSlug: 'camera',
        children: [
          BridgeMediaSource(
            bridge: bridge,
            id: 'camera.images',
            displayName: 'Images',
            subtitle: 'Camera photos',
            destinationSlug: 'camera',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: 'camera.videos',
            displayName: 'Videos',
            subtitle: 'Camera videos',
            destinationSlug: 'camera',
          ),
        ],
      ),
      BridgeMediaSource(
        bridge: bridge,
        id: 'screenshots',
        displayName: 'Screenshots',
        subtitle: 'DCIM & Pictures/Screenshots',
        destinationSlug: 'screenshots',
      ),
      BridgeMediaSource(
        bridge: bridge,
        id: 'whatsapp',
        displayName: 'WhatsApp',
        subtitle: 'Received & Sent media',
        destinationSlug: 'whatsapp',
        children: [
          BridgeMediaSource(
            bridge: bridge,
            id: 'whatsapp.received',
            displayName: 'Received',
            subtitle: 'Incoming WhatsApp media',
            destinationSlug: 'whatsapp/received',
            children: [
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.received.images',
                displayName: 'Images',
                subtitle: 'WhatsApp Images',
                destinationSlug: 'whatsapp/received/images',
              ),
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.received.videos',
                displayName: 'Videos',
                subtitle: 'WhatsApp Video',
                destinationSlug: 'whatsapp/received/videos',
              ),
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.received.audios',
                displayName: 'Audios & Voice Notes',
                subtitle: 'WhatsApp Audio & Voice Notes',
                destinationSlug: 'whatsapp/received/audios',
              ),
            ],
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: 'whatsapp.sent',
            displayName: 'Sent',
            subtitle: 'Outgoing WhatsApp media',
            destinationSlug: 'whatsapp/sent',
            children: [
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.sent.images',
                displayName: 'Images',
                subtitle: 'WhatsApp Images/Sent',
                destinationSlug: 'whatsapp/sent/images',
              ),
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.sent.videos',
                displayName: 'Videos',
                subtitle: 'WhatsApp Video/Sent',
                destinationSlug: 'whatsapp/sent/videos',
              ),
              BridgeMediaSource(
                bridge: bridge,
                id: 'whatsapp.sent.audios',
                displayName: 'Audios',
                subtitle: 'WhatsApp Audio/Sent',
                destinationSlug: 'whatsapp/sent/audios',
              ),
            ],
          ),
        ],
      ),
      BridgeMediaSource(
        bridge: bridge,
        id: 'recordings',
        displayName: 'Recorded Audios',
        subtitle: 'Voice Recorder & Recordings',
        destinationSlug: 'recordings',
      ),
    ];
