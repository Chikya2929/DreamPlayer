import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_updater.dart';

/// The in-app update prompt. Covers the whole sideload flow: notes, download
/// with progress, the "install unknown apps" prompt, and the final installer
/// hand-off.
Future<void> showAppUpdateDialog(BuildContext context, AvailableUpdate update) {
  return showDialog<void>(
    context: context,
    // Dismissing mid-download would leave an orphaned transfer with no UI to
    // cancel it. The prompt itself has a Later button.
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(update: update),
  );
}

enum _Phase { prompt, downloading, permission, error }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AvailableUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.prompt;
  double? _progress;
  bool _cancelled = false;
  String? _error;
  File? _apk;

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _cancelled = false;
      _error = null;
    });
    try {
      final apk = await AppUpdater.download(
        widget.update,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          if (!mounted || _cancelled) return;
          // A 100 MB transfer emits thousands of chunks; only repaint when the
          // shown percentage actually moves.
          if (p != null && p < 1 && _progress != null) {
            final shown = (_progress! * 100).floor();
            final next = (p * 100).floor();
            if (shown == next) return;
          }
          setState(() => _progress = p);
        },
      );
      if (!mounted || _cancelled) return;
      _apk = apk;
      await _install(apk);
    } catch (e) {
      if (!mounted || _cancelled) {
        if (mounted && _cancelled) {
          setState(() {
            _cancelled = false;
            _phase = _Phase.prompt;
          });
        }
        return;
      }
      setState(() {
        _phase = _Phase.error;
        _error = e is SocketException ? 'Check your connection and try again.' : 'Download failed.';
      });
    }
  }

  Future<void> _install(File apk) async {
    try {
      await AppUpdater.install(apk);
      if (mounted) Navigator.of(context).pop();
    } on UpdatePermissionRequired {
      if (mounted) setState(() => _phase = _Phase.permission);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.message ?? 'The installer could not be opened.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _phase != _Phase.downloading,
      child: AlertDialog(
        title: Text(switch (_phase) {
          _Phase.permission => 'Allow installs',
          _ => 'Update available',
        }),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SizedBox(
            width: double.maxFinite,
            child: switch (_phase) {
              _Phase.prompt => _prompt(theme),
              _Phase.downloading => _downloading(theme),
              _Phase.permission => _permission(theme),
              _Phase.error => Text(_error ?? 'Something went wrong.'),
            },
          ),
        ),
        actions: _actions(),
      ),
    );
  }

  Widget _prompt(ThemeData theme) {
    final update = widget.update;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DreamPlayer ${update.version} is available. '
          'You have ${update.installedVersion}.',
          style: theme.textTheme.bodyMedium,
        ),
        if (update.needsOneTimeUninstall) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This release uses a new signing key. If the install is '
                  'refused, uninstall the old app once and install again. '
                  'Uninstalling clears DreamPlayer\'s settings and resume '
                  'positions; your video files are untouched.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (update.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Text(
                update.notes,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _downloading(ThemeData theme) {
    final progress = _progress;
    final percent = progress == null ? null : (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          percent == null ? 'Downloading the update…' : 'Downloading the update… $percent%',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: progress),
        ),
        const SizedBox(height: 12),
        Text(
          'The install screen opens when it finishes.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _permission(ThemeData theme) {
    return Text(
      'Android needs permission for DreamPlayer to install the update. '
      'Turn on "Allow from this source" in the screen that opens, then come '
      'back and tap Install.',
      style: theme.textTheme.bodyMedium,
    );
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.prompt:
        return [
          TextButton(
            onPressed: () async {
              await AppUpdater.skipVersion(widget.update.version);
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Skip this version'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text('Update now'),
          ),
        ];
      case _Phase.downloading:
        return [
          TextButton(
            onPressed: () => setState(() {
              _cancelled = true;
              _phase = _Phase.prompt;
            }),
            child: const Text('Cancel'),
          ),
        ];
      case _Phase.permission:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: AppUpdater.openInstallPermissionSettings,
            child: const Text('Open settings'),
          ),
          FilledButton(
            onPressed: _apk == null ? null : () => _install(_apk!),
            child: const Text('Install'),
          ),
        ];
      case _Phase.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text('Try again'),
          ),
        ];
    }
  }
}
