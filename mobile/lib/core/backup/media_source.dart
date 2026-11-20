import '../config/custom_folder_config.dart';
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

/// Extensible hierarchical contract for backup media sources and sub-items.
abstract class MediaSource {
  String get id;
  String get displayName;
  String get subtitle;
  String get destinationSlug;
  List<MediaSource> get children;

  bool get isGroup => children.isNotEmpty;

  Set<String> get leafIds {
    if (!isGroup) return {id};
    final out = <String>{};
    for (final child in children) {
      out.addAll(child.leafIds);
    }
    return out;
  }

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

  Future<List<BackupItem>> discoverItems({int? perSourceLimit});
}

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

/// High-signal personal sources enabled by default.
/// Noisy/opt-in sources (Downloads, WhatsApp Business, Telegram, Device Snapshots)
/// start unchecked until the user toggles them on (and persist across sessions once toggled).
const Set<String> defaultEnabledMediaSourceIds = {
  'camera.images',
  'camera.videos',
  'camera.raw',
  'screenshots',
  'screen_recordings',
  'whatsapp.received.images',
  'whatsapp.received.videos',
  'whatsapp.received.audios',
  'whatsapp.received.documents',
  'whatsapp.sent.images',
  'whatsapp.sent.videos',
  'whatsapp.sent.audios',
  'whatsapp.sent.documents',
  'recordings',
  'documents',
  'editors.lightroom',
  'editors.snapseed',
  'editors.instagram',
  'editors.other',
};

const Set<String> snapshotSourceIds = {
  'snapshots.contacts',
  'snapshots.sms',
  'snapshots.call_logs',
};

BridgeMediaSource _whatsAppTree(
  NativeBackupBridge bridge, {
  required String idPrefix,
  required String title,
  required String remotePrefix,
}) {
  return BridgeMediaSource(
    bridge: bridge,
    id: idPrefix,
    displayName: title,
    subtitle: 'Received & Sent media and documents',
    destinationSlug: remotePrefix,
    children: [
      BridgeMediaSource(
        bridge: bridge,
        id: '$idPrefix.received',
        displayName: 'Received',
        subtitle: 'Incoming media & documents',
        destinationSlug: '$remotePrefix/received',
        children: [
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.received.images',
            displayName: 'Images',
            subtitle: '$title Images',
            destinationSlug: '$remotePrefix/received/images',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.received.videos',
            displayName: 'Videos',
            subtitle: '$title Video',
            destinationSlug: '$remotePrefix/received/videos',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.received.audios',
            displayName: 'Audios & Voice Notes',
            subtitle: '$title Audio & Voice Notes',
            destinationSlug: '$remotePrefix/received/audios',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.received.documents',
            displayName: 'Documents',
            subtitle: '$title Documents (PDF, Office, etc.)',
            destinationSlug: '$remotePrefix/received/documents',
          ),
        ],
      ),
      BridgeMediaSource(
        bridge: bridge,
        id: '$idPrefix.sent',
        displayName: 'Sent',
        subtitle: 'Outgoing media & documents',
        destinationSlug: '$remotePrefix/sent',
        children: [
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.sent.images',
            displayName: 'Images',
            subtitle: '$title Images/Sent',
            destinationSlug: '$remotePrefix/sent/images',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.sent.videos',
            displayName: 'Videos',
            subtitle: '$title Video/Sent',
            destinationSlug: '$remotePrefix/sent/videos',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.sent.audios',
            displayName: 'Audios',
            subtitle: '$title Audio/Sent',
            destinationSlug: '$remotePrefix/sent/audios',
          ),
          BridgeMediaSource(
            bridge: bridge,
            id: '$idPrefix.sent.documents',
            displayName: 'Documents',
            subtitle: '$title Documents/Sent',
            destinationSlug: '$remotePrefix/sent/documents',
          ),
        ],
      ),
    ],
  );
}

/// Full hierarchical registry of built-in and user-configured [MediaSource] trees.
List<MediaSource> buildMediaSources(
  NativeBackupBridge bridge, {
  List<CustomFolderConfig> customFolders = const [],
}) {
  return [
    BridgeMediaSource(
      bridge: bridge,
      id: 'camera',
      displayName: 'Camera',
      subtitle: 'DCIM/Camera & Expert RAW',
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
        BridgeMediaSource(
          bridge: bridge,
          id: 'camera.raw',
          displayName: 'Expert RAW',
          subtitle: 'DCIM/Expert RAW (.dng)',
          destinationSlug: 'camera/raw',
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
      id: 'screen_recordings',
      displayName: 'Screen Recordings',
      subtitle: 'DCIM/Screen recordings & Movies/Screenrecords',
      destinationSlug: 'screen-recordings',
    ),
    _whatsAppTree(
      bridge,
      idPrefix: 'whatsapp',
      title: 'WhatsApp',
      remotePrefix: 'whatsapp',
    ),
    _whatsAppTree(
      bridge,
      idPrefix: 'whatsapp_business',
      title: 'WhatsApp Business',
      remotePrefix: 'whatsapp-business',
    ),
    BridgeMediaSource(
      bridge: bridge,
      id: 'telegram',
      displayName: 'Telegram',
      subtitle: 'Images, Videos, Audios & Documents',
      destinationSlug: 'telegram',
      children: [
        BridgeMediaSource(
          bridge: bridge,
          id: 'telegram.images',
          displayName: 'Images',
          subtitle: 'Telegram Images',
          destinationSlug: 'telegram/images',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'telegram.videos',
          displayName: 'Videos',
          subtitle: 'Telegram Video',
          destinationSlug: 'telegram/videos',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'telegram.audios',
          displayName: 'Audios',
          subtitle: 'Telegram Audio',
          destinationSlug: 'telegram/audios',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'telegram.documents',
          displayName: 'Documents',
          subtitle: 'Telegram Documents',
          destinationSlug: 'telegram/documents',
        ),
      ],
    ),
    BridgeMediaSource(
      bridge: bridge,
      id: 'editors',
      displayName: 'Photo Editors & Social',
      subtitle: 'Lightroom, Snapseed, Instagram & Restored',
      destinationSlug: 'editors',
      children: [
        BridgeMediaSource(
          bridge: bridge,
          id: 'editors.lightroom',
          displayName: 'Lightroom',
          subtitle: 'Pictures/Lightroom',
          destinationSlug: 'editors/lightroom',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'editors.snapseed',
          displayName: 'Snapseed',
          subtitle: 'Pictures/Snapseed',
          destinationSlug: 'editors/snapseed',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'editors.instagram',
          displayName: 'Instagram',
          subtitle: 'Pictures & Movies/Instagram',
          destinationSlug: 'editors/instagram',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'editors.other',
          displayName: 'Restored & Canva',
          subtitle: 'DCIM/Restored, Canva, Pinterest',
          destinationSlug: 'editors/other',
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
    BridgeMediaSource(
      bridge: bridge,
      id: 'documents',
      displayName: 'Documents',
      subtitle: 'Internal /Documents folder',
      destinationSlug: 'documents',
    ),
    BridgeMediaSource(
      bridge: bridge,
      id: 'downloads',
      displayName: 'Downloads',
      subtitle: '/Download (opt-in)',
      destinationSlug: 'downloads',
      children: [
        BridgeMediaSource(
          bridge: bridge,
          id: 'downloads.media',
          displayName: 'Images & Videos',
          subtitle: 'Downloaded photos & videos',
          destinationSlug: 'downloads/media',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'downloads.documents',
          displayName: 'Documents & PDFs',
          subtitle: 'PDF, Office, CSV, Markdown',
          destinationSlug: 'downloads/documents',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'downloads.other',
          displayName: 'Other Files',
          subtitle: 'Archives, APKs & other downloads',
          destinationSlug: 'downloads/other',
        ),
      ],
    ),
    BridgeMediaSource(
      bridge: bridge,
      id: 'snapshots',
      displayName: 'Device Snapshots',
      subtitle: 'Read-only Contacts, SMS & Call Logs exports',
      destinationSlug: 'snapshots',
      children: [
        BridgeMediaSource(
          bridge: bridge,
          id: 'snapshots.contacts',
          displayName: 'Contacts (.vcf)',
          subtitle: 'Export contacts vCard snapshot',
          destinationSlug: 'snapshots/contacts',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'snapshots.sms',
          displayName: 'SMS Messages (.json)',
          subtitle: 'Export SMS snapshot',
          destinationSlug: 'snapshots/sms',
        ),
        BridgeMediaSource(
          bridge: bridge,
          id: 'snapshots.call_logs',
          displayName: 'Call Logs (.json)',
          subtitle: 'Export call history snapshot',
          destinationSlug: 'snapshots/call-logs',
        ),
      ],
    ),
    if (customFolders.isNotEmpty)
      BridgeMediaSource(
        bridge: bridge,
        id: 'custom',
        displayName: 'Custom Folders',
        subtitle: 'User-configured device folders',
        destinationSlug: 'custom',
        children: [
          for (final folder in customFolders)
            BridgeMediaSource(
              bridge: bridge,
              id: folder.id,
              displayName: folder.displayName,
              subtitle: folder.relativePath,
              destinationSlug: 'custom/${folder.slug}',
            ),
        ],
      ),
  ];
}

List<MediaSource> defaultMediaSources(NativeBackupBridge bridge) =>
    buildMediaSources(bridge);
