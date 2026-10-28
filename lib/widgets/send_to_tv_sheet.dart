import 'package:flutter/material.dart';

import '../models/video_item.dart';
import '../services/cast_coordinator.dart';
import '../services/cast_manager.dart';
import '../services/dlna_client.dart';
import '../services/dream_cast_client.dart';

/// Pulls the cast state used by the unified sheet, so the widget tree reads
/// through one object (the coordinator also mirrors Google Cast state).
/// The [CastCoordinator] instance is a ChangeNotifier — the caller listens
/// to freshness.
class SendToTvSheet extends StatefulWidget {
  const SendToTvSheet({
    super.key,
    required this.video,
    required this.positionMs,
    required this.title,
  });

  final VideoItem video;
  final int positionMs;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required VideoItem video,
    required int positionMs,
    required String title,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (dialogContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SendToTvSheet(
            video: video,
            positionMs: positionMs,
            title: title,
          ),
        ),
      ),
    );
  }

  @override
  State<SendToTvSheet> createState() => _SendToTvSheetState();
}

class _SendToTvSheetState extends State<SendToTvSheet> {
  final CastCoordinator coordinator = CastCoordinator.instance;
  bool discovering = true;
  List<DlnaTarget> dlnaTargets = [];
  List<DreamCastTarget> dreamTargets = [];
  String? statusText;

  @override
  void initState() {
    super.initState();
    CastManager.instance.refreshState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() {
      discovering = true;
      statusText = null;
    });
    final dlnaFuture = coordinator.dlna.discover();
    final dreamFuture = coordinator.dream.discover();
    final dlnaResults = await dlnaFuture;
    final dreamResults = await dreamFuture;
    if (!mounted) return;
    setState(() {
      dlnaTargets = dlnaResults;
      dreamTargets = dreamResults;
      discovering = false;
    });
  }

  Future<void> _cast(String Function() label, Future<bool> Function() action) async {
    setState(() => statusText = 'Connecting…');
    final ok = await action();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => statusText = '${label()} refused the connection.');
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = castEligibility(widget.video);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.cast),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Play on TV',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Search again',
                onPressed: discovering ? null : _discover,
              ),
            ],
          ),
        ),
        if (statusText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              statusText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (coordinator.isCasting)
          ListTile(
            leading: const Icon(Icons.cast_connected),
            title: Text('Stop casting to ${coordinator.deviceName ?? 'device'}'),
            onTap: () async {
              await coordinator.stop();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        if (eligibility == CastEligibility.directPlayable)
          ListTile(
            leading: const Icon(Icons.cast),
            title: const Text('Chromecast / Google TV…'),
            subtitle: const Text(
                'Opens the system Cast device picker (native receivers).'),
            onTap: () {
              Navigator.of(context).pop();
              CastManager.instance.openPicker();
            },
          ),
        if (eligibility == CastEligibility.needsLocalServer)
          ListTile(
            leading: const Icon(Icons.cast),
            title: const Text('Chromecast / Google TV…'),
            subtitle: const Text(
                'Castable only after the LAN media server — skip for now.'),
            enabled: false,
            onTap: null,
          ),
        if (!discovering && dreamTargets.isEmpty && dlnaTargets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No DreamPlayer or DLNA TVs found on this network.'),
          ),
        for (final target in dreamTargets)
          ListTile(
            leading: const Icon(Icons.tv),
            title: Text(target.name),
            subtitle: const Text('DreamPlayer sender'),
            onTap: () => _cast(
              () => target.name,
              () => coordinator.castToDreamCast(
                target,
                CastRequest(
                  video: widget.video,
                  positionMs: widget.positionMs,
                  title: widget.title,
                ),
              ),
            ),
          ),
        for (final target in dlnaTargets)
          ListTile(
            leading: const Icon(Icons.tv),
            title: Text(target.name),
            subtitle: target.model.isEmpty ? null : Text(target.model),
            onTap: () => _cast(
              () => target.name,
              () => coordinator.castToDlna(
                target,
                CastRequest(
                  video: widget.video,
                  positionMs: widget.positionMs,
                  title: widget.title,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

}
