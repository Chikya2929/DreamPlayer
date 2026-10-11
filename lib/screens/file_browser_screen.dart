import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_item.dart';
import '../services/download_manager.dart';
import '../services/file_browser.dart';
import '../services/tmdb_client.dart';
import '../services/resume_progress_helper.dart';
import '../services/watched_store.dart';
import '../utils/file_info_extractor.dart';
import '../widgets/tv_overscan.dart';
import '../widgets/episode_row.dart';
import '../widgets/tv_tile.dart';
import 'tmd_details_screen.dart';
import '../l10n/app_localizations.dart';

/// In-app file browser (CX-Explorer style): browse the device's storage and
/// play any video without importing it into the library.
class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with WidgetsBindingObserver {
  static final FileBrowserService _service = FileBrowserService.instance;

  List<FileEntry> _roots = const [];
  String? _currentPath;
  List<FileEntry> _entries = const [];
  bool _loading = true;
  bool _hasAccess = true;
  String? _error;

  /// Watched marks for the current folder, keyed by each file's stable resume
  /// key for playback.
  Set<String> _watchedKeys = {};

  Map<String, int> _resumePositionsMs = {};
  Map<String, int> _durationsMs = {};

  bool get _atRoot => _currentPath == null;

  /// Paths selected by long-press (issue #48 follow-up).
  ///
  /// Selection is keyed by path, not by index, so it survives a rescan — the
  /// roots list is rebuilt every time a drive is plugged in or the screen
  /// resumes.
  final Set<String> _selected = <String>{};
  bool get _selectionActive => _selected.isNotEmpty;

  void _toggleSelect(FileEntry entry) {
    setState(() {
      if (!_selected.add(entry.path)) _selected.remove(entry.path);
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TmdService.instance.addListener(_onTmdbChanged);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TmdService.instance.removeListener(_onTmdbChanged);
    super.dispose();
  }

  void _onTmdbChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshWatched() async {
    try {
      final watched = await WatchedStore.load();
      if (mounted) setState(() => _watchedKeys = watched);
    } catch (_) {}
    await _refreshResumes();
  }

  Future<void> _refreshResumes() async {
    final keys = <String>{};
    for (final e in _entries) {
      if (e.isDirectory) continue;
      if (e.resumeKey != null && e.resumeKey!.isNotEmpty) keys.add(e.resumeKey!);
      if (e.path.isNotEmpty) keys.add(e.path);
    }
    if (keys.isEmpty) return;
    try {
      final result = await ResumeProgressHelper.load(keys.toList());
      if (mounted) {
        setState(() {
          _resumePositionsMs = result.positions;
          _durationsMs = result.durations;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleWatched(FileEntry entry) async {
    final key = entry.resumeKey ?? entry.path;
    if (entry.isDirectory || key.isEmpty) return;
    final now = !_watchedKeys.contains(key);
    setState(() {
      _watchedKeys = {..._watchedKeys};
      now ? _watchedKeys.add(key) : _watchedKeys.remove(key);
    });
    try {
      await WatchedStore.set(key, now);
    } catch (_) {}
  }

  @override
  /// Re-scan on every resume, not just when All Files Access is missing.
  ///
  /// Issue #48: a USB drive plugged in while the app was in the background
  /// never appeared, because the resume handler only re-ran `_init` when
  /// access was missing — and a user with access already granted stayed on the
  /// root list computed before the drive existed. Resuming is also the moment
  /// the platform finishes mounting the volume, so this is where a rescan
  /// belongs.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_hasAccess) {
      _init();
      return;
    }
    if (_currentPath == null) {
      _loadRoots();
    } else {
      // Inside a folder: re-list it so files copied onto a freshly mounted
      // drive show up too.
      _load(_currentPath!);
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hasAccess = await _service.hasAllFilesAccess();
      if (!hasAccess) {
        if (mounted) {
          setState(() {
            _hasAccess = false;
            _loading = false;
          });
        }
        return;
      }
      _hasAccess = true;
      if (_currentPath == null) {
        await _loadRoots();
      } else {
        await _load(_currentPath!);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Something went wrong';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRoots() async {
    final roots = await _service.storageRoots();
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _entries = roots;
      _loading = false;
    });
    _prefetchTmdb(roots);
  }

  Future<void> _load(String path) async {
    final entries = await _service.listDirectory(path);
    if (!mounted) return;
    setState(() {
      _currentPath = path;
      _entries = entries;
      _loading = false;
    });
    _prefetchTmdb(entries);
    await _refreshWatched();
  }

  void _prefetchTmdb(List<FileEntry> entries) {
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      TmdService.instance.resolve(_toVideoItem(entry)).catchError((_) {
        return null;
      });
    }
  }

  Future<void> _openEntry(FileEntry entry) async {
    if (entry.isDirectory) {
      if (entry.isFilesHome) {
        // iOS: the virtual "Files" root — open the system Files-app home and
        // play whatever video the user picks.
        final picked = await _service.openFilesHome();
        if (picked == null || !mounted) return;
        _playVideo(picked);
        return;
      }
      setState(() => _loading = true);
      await _load(entry.path);
    } else {
      _playVideo(entry);
    }
  }

  /// Opens a video's details page first (TMDB metadata + Play/Resume button),
  /// like the WebDAV/Jellyfin browsers.
  Future<void> _playVideo(FileEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TmdDetailsScreen(video: _toVideoItem(entry)),
      ),
    );
    _refreshResumes();
  }

  VideoItem _toVideoItem(FileEntry entry) {
    // Bookmarked-tree videos come back as content:// URIs (no real file
    // path), so hand those to the player's `uri` field.
    final isContentUri = entry.path.startsWith('content://');
    final info = extractFileInfo(entry.name);
    return VideoItem(
      id: 'file_${entry.path.hashCode}',
      title: entry.name,
      path: isContentUri ? null : entry.path,
      uri: isContentUri ? entry.path : null,
      resumeKey: entry.resumeKey,
      duration: Duration.zero,
      sizeBytes: entry.size,
      videoCodec: info.videoCodec,
      audioCodec: info.audioCodec,
      audioChannels: info.audioChannels,
      audioLanguage: info.audioLanguage,
      resolution: info.resolution,
      fps: info.fps,
      hdrHint: info.hdrHint,
    );
  }

  Future<void> _goUp() async {
    if (_atRoot) {
      Navigator.of(context).pop();
      return;
    }
    final rootPaths = _roots.map((r) => r.path).toSet();
    final parent = _parentOf(_currentPath);
    // Currently viewing a root's contents: back to the roots list.
    if (rootPaths.contains(_currentPath) || parent == null) {
      setState(() {
        _currentPath = null;
        _entries = _roots;
        _loading = false;
      });
      return;
    }
    // One level up. When the parent is itself a root, still show its contents
    // (the page you came from) rather than skipping to the roots list.
    setState(() => _loading = true);
    await _load(parent);
  }

  /// Forgets a bookmarked folder.
  Future<void> _removeBookmark(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).fileBrowseRemoveFolder),
        content: Text(
          '"${entry.name}" will no longer appear here. You can add it again '
          'anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.of(context).commonRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.removeBookmark(entry.bookmarkId!);
      await _loadRoots();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not remove the folder');
      }
    }
  }

  static String? _parentOf(String? path) {
    if (path == null) return null;
    final index = path.lastIndexOf('/');
    if (index <= 0) return null;
    return path.substring(0, index);
  }

  /// Single-file "Download to device" from a row's own button.
  ///
  /// Same destination as the network downloader, so a file pulled off a USB
  /// drive lands beside everything else in `<Downloads>/DreamPlayer/`.
  Future<void> _copyOneToDownloads(FileEntry entry) async {
    // Routed through DownloadManager, NOT a direct channel call: a large file
    // copied on the platform thread froze the app, and the copy produced no
    // progress, no notification and no home-screen entry. This is the same
    // path an SMB download takes, so all three come for free.
    await _enqueueCopies([entry]);
  }

  /// Copies every selected item into `<Downloads>/DreamPlayer/`.
  ///
  /// The browser-side "Download to device": the network downloader already
  /// writes there, so a file copied off a USB drive joins the same folder and
  /// shows up in the downloads list with everything else.
  Future<void> _copySelectionToDownloads() async {
    final paths = _selected.toList();
    if (paths.isEmpty) return;
    await _enqueueCopies(
      paths.map((p) => _entries.firstWhere((e) => e.path == p)).toList(),
    );
  }

  /// Queues [entries] as downloads into `<Downloads>/DreamPlayer/`.
  ///
  /// DownloadManager runs them one at a time with a progress bar, a foreground
  /// notification and a row on the home screen's downloads list — identical to
  /// an SMB download. Folders are skipped: a recursive copy is not a single
  /// file transfer, and queueing it as one job would report a size it does not
  /// know and cannot cancel meaningfully.
  Future<void> _enqueueCopies(List<FileEntry> entries) async {
    final manager = DownloadManager.instance;
    var queued = 0;
    final skipped = entries.where((e) => e.isDirectory).length;
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      try {
        await manager.startDownload(_toVideoItem(entry));
        queued++;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start: ${entry.name}')),
        );
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final parts = <String>[
      if (queued > 0) 'Downloading ${queued == 1 ? '1 file' : '$queued files'}'
          ' to Download/DreamPlayer',
      if (skipped > 0) 'skipped $skipped '
          '${skipped == 1 ? 'folder' : 'folders'}',
    ];
    messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }

  /// Deletes every selected file, after one confirmation for the whole batch.
  ///
  /// Irreversible, so the dialog names the count rather than "are you sure",
  /// and the action is deliberately behind long-press + the overflow rather
  /// than a swipe, so it cannot be hit by accident while scrolling.
  Future<void> _confirmDeleteSelection() async {
    final paths = _selected.toList();
    if (paths.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${paths.length} '
            '${paths.length == 1 ? 'item' : 'items'}?'),
        content: Text(
          _containsFolder
              ? 'This permanently deletes the selected items, INCLUDING the '
                  'contents of any folder, from the device. It cannot be '
                  'undone.'
              : 'This permanently deletes the selected files from the device. '
                  'It cannot be undone.',
          style: const TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    int deleted = 0;
    final failures = <String>[];
    for (final path in paths) {
      final failure = await FileBrowserService.instance.deleteLocalFile(path);
      if (failure == null) {
        deleted++;
      } else {
        failures.add(failure);
      }
    }
    _clearSelection();
    if (!mounted) return;
    // Re-list so the rows actually disappear; a local delete bypasses every
    // cache, so there is nothing to invalidate.
    if (_currentPath == null) {
      await _loadRoots();
    } else {
      await _load(_currentPath!);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? 'Deleted ${deleted == 1 ? '1 item' : '$deleted items'}'
              : 'Deleted $deleted, failed ${failures.length}',
        ),
      ),
    );
  }

  /// True when the current selection includes a folder, which makes the
  /// delete confirmation say so explicitly — a recursive delete of a folder's
  /// contents must never look like a plain file delete.
  bool get _containsFolder =>
      _selected.any((path) => _entries.any((e) => e.path == path && e.isDirectory));

  void _grantAccess() {
    _service.openAllFilesAccessSettings();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _goUp();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_atRoot
            ? 'Browse files'
            : (_currentPath?.split('/').lastOrNull ?? 'Files')),
        leading: IconButton(
          tooltip: _selectionActive ? 'Cancel selection' : 'Up',
          icon: Icon(_selectionActive ? Icons.close : Icons.arrow_back),
          onPressed: _selectionActive ? _clearSelection : _goUp,
        ),
        actions: [
          if (_selectionActive) ...[
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text('${_selected.length} selected'),
              ),
            ),
            // The overflow the user asked for: select by long-press, then act
            // from the three dots.
            PopupMenuButton<String>(
              key: ValueKey('fileSelectionMenu'),
              icon: const Icon(Icons.more_vert),
              tooltip: 'Selection actions',
              onSelected: (value) {
                if (value == 'delete') _confirmDeleteSelection();
                if (value == 'download') _copySelectionToDownloads();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.download_outlined),
                    title: Text('Download to device'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: TvOverscan(child: _body(context)),
    ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('Error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (!_hasAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 64),
              SizedBox(height: 16),
              Text(
                'All files access is needed to browse your storage',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: 16),
              FilledButton(
                onPressed: _grantAccess,
                child: Text('Grant access'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(child: Text('No videos or folders here'));
    }
    final items = <Widget>[
      for (final entry in _entries)
        _FileTile(
          entry: entry,
          selected: _selected.contains(entry.path),
          selectionActive: _selectionActive,
          onTap: _selectionActive
              ? () => _toggleSelect(entry)
              : () => _openEntry(entry),
          onLongPress: () => _toggleSelect(entry),
          onRemove: _atRoot && entry.bookmarkId != null
              ? () => _removeBookmark(entry)
              : null,
          tmdbMeta: TmdService.instance.metaFor(
            TmdStore.identityKeyFor(_toVideoItem(entry)),
          ),
          watched: !entry.isDirectory &&
              _watchedKeys.contains(entry.resumeKey ?? entry.path),
          onToggleWatched:
              entry.isDirectory ? null : () => _toggleWatched(entry),
          // Same "Download to device" the player offers, per file, so a USB
          // copy does not need selection mode first.
          onDownload: _copyOneToDownloads,
          resumeProgress: entry.isDirectory
              ? null
              : ResumeProgressHelper.progressFor(
                  entry.resumeKey?.isNotEmpty == true
                      ? entry.resumeKey!
                      : entry.path,
                  _resumePositionsMs,
                  _durationsMs,
                ),
        ),
    ];
    if (_atRoot) {
      // Explicit re-scan (issue #48). A USB drive mounted while the app was
      // already open is picked up on resume, but "I plugged it in and nothing
      // happened" deserves a button as well as an automatic rescan.
      items.add(
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('Rescan drives'),
          subtitle: const Text('Pick up newly connected USB drives'),
          onTap: () {
            if (_currentPath == null) {
              _loadRoots();
            } else {
              _load(_currentPath!);
            }
          },
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }
}


class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.entry,
    required this.onTap,
    this.onRemove,
    this.tmdbMeta,
    this.watched = false,
    this.onToggleWatched,
    this.resumeProgress,
    this.selected = false,
    this.selectionActive = false,
    this.onLongPress,
    this.onDownload,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool selected;
  final bool selectionActive;
  final VoidCallback? onLongPress;

  /// Per-file "Download to device", mirroring the player action.
  final void Function(FileEntry entry)? onDownload;
  final TmdMeta? tmdbMeta;
  final bool watched;
  final VoidCallback? onToggleWatched;
  final double? resumeProgress;

  static String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entry.isDirectory) {
      return TvTile(
        leading: Icon(Icons.folder, color: colorScheme.primary),
        title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove folder',
                onPressed: onRemove,
              )
            else
              const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        selected: selected,
      );
    }

    final parsed = ParsedFileName.parse(entry.name);
    final effectiveLabel = parsed.isEpisode
        ? 'S${parsed.season.toString().padLeft(2, '0')}E${parsed.episode.toString().padLeft(2, '0')}'
        : '';

    final posterUrl = posterUrlOf(tmdbMeta);

    final filenameWidget = Text(
      entry.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
    );

    final titleWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (parsed.isEpisode) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              effectiveLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            parsed.isEpisode
                ? (tmdbMeta?.movie.title.isNotEmpty == true
                    ? tmdbMeta!.movie.title
                    : parsed.title)
                : (tmdbMeta?.movie.title.isNotEmpty == true
                    ? tmdbMeta!.movie.title
                    : entry.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        if (tmdbMeta != null && tmdbMeta!.movie.voteAverage > 0) ...[
          SizedBox(width: 6),
          const Icon(Icons.star, size: 13, color: Colors.amber),
          SizedBox(width: 2),
          Text(
            tmdbMeta!.movie.voteAverage.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final subtitleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        filenameWidget,
        if (_sizeLabel(entry.size).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _sizeLabel(entry.size),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (resumeProgress != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: resumeProgress,
                minHeight: 2,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ),
      ],
    );

    return EpisodeRow(
      thumbBuilder: (size) => EpisodePosterThumb(
        posterUrl: posterUrl,
        size: size,
      ),
      title: titleWidget,
      subtitle: subtitleWidget,
      // Watch + remove + download.
      trailingWidth: 144,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleWatched != null)
            IconButton(
              tooltip: watched ? 'Mark as unwatched' : 'Mark as watched',
              icon: Icon(
                watched ? Icons.check_circle : Icons.check_circle_outline,
                color: watched
                    ? Colors.green.shade400
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: onToggleWatched,
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove folder',
              onPressed: onRemove,
            ),
          if (onDownload != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download to device',
              onPressed: () => onDownload!(entry),
            ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      // The watch toggle is meaningless mid-selection; the row tap and the
      // overflow do the work then.
      showTrailingActions: !selectionActive,
    );
  }
}
