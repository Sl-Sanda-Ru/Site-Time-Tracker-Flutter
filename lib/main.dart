import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'note_model.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const int ongoingNotificationId = 0;
const String notificationChannelId = 'tracking_channel';
const String notificationChannelName = 'Tracking';

const _defaultColor = Colors.indigo;

String formatDuration(String startIso, String? endIso) {
  try {
    final start = DateTime.parse(startIso);
    final end = endIso != null ? DateTime.parse(endIso) : DateTime.now();
    final diff = end.difference(start);

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  } catch (_) {
    return '';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
  );
  await notificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel startChannel = AndroidNotificationChannel(
    'start_channel',
    'Note Start',
    description: 'Plays sound when a note starts',
    importance: Importance.high, // show heads-up + sound
    playSound: true,
    enableVibration: true,
  );

  const AndroidNotificationChannel trackingChannel = AndroidNotificationChannel(
    notificationChannelId,
    notificationChannelName,
    description: 'Ongoing tracking notification',
    importance: Importance.low, // quiet updates
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );
  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(startChannel);

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(trackingChannel);

  runApp(const NotesApp());
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    setState(() {
      _themeMode = ThemeMode.values[themeIndex];
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', ThemeMode.values.indexOf(mode));
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightColorScheme =
            lightDynamic?.harmonized() ??
            ColorScheme.fromSwatch(
              primarySwatch: _defaultColor,
              brightness: Brightness.light,
            );
        final darkColorScheme =
            darkDynamic?.harmonized() ??
            ColorScheme.fromSwatch(
              primarySwatch: _defaultColor,
              brightness: Brightness.dark,
            );

        return MaterialApp(
          title: 'Location Timer Notes',
          theme: ThemeData(useMaterial3: true, colorScheme: lightColorScheme),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkColorScheme,
          ),
          themeMode: _themeMode,
          home: NotesPage(themeMode: _themeMode, onThemeChanged: _setTheme),
        );
      },
    );
  }
}

class NotesPage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const NotesPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> _notes = [];
  late File _jsonFile;
  final String _fileName = 'notes.json';
  bool _fileReady = false;
  bool _isGridView = false;
  Timer? _timer;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _initFileAndNotes();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_notes.any((note) => note.endTime == null)) {
        setState(() {});
      }
    });
    _notificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final ongoing = _notes.where((n) => n.endTime == null).toList();
      if (ongoing.isNotEmpty) {
        _showOngoingNotification(ongoing.last);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyReportToClipboard() async {
    try {
      final buffer = StringBuffer();

      for (final note in _notes) {
        final start = DateTime.parse(note.startTime).toLocal();
        final end = note.endTime != null
            ? DateTime.parse(note.endTime!).toLocal()
            : null;
        final duration = formatDuration(note.startTime, note.endTime);

        buffer.writeln(
          "${start.toLocal().toString().split(' ').first} | ${note.address}",
        );
        buffer.writeln(
          "From ${start.toString().split('.').first} → ${end != null ? end.toString().split('.').first : 'Ongoing'}",
        );
        buffer.writeln("Duration: $duration");
        buffer.writeln(""); // blank line between notes
      }

      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report copied to clipboard')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to copy report: $e')));
      }
    }
  }

  Future<void> _initFileAndNotes() async {
    Directory dir = await getApplicationDocumentsDirectory();
    _jsonFile = File('${dir.path}/$_fileName');

    if (!await _jsonFile.exists()) {
      await _jsonFile.create(recursive: true);
      await _jsonFile.writeAsString(json.encode([]));
    }

    final String contents = await _jsonFile.readAsString();
    final List<dynamic> jsonData = json.decode(contents);
    _notes = jsonData.map((e) => Note.fromJson(e)).toList();

    final ongoing = _notes.where((n) => n.endTime == null).toList();
    if (ongoing.isNotEmpty) {
      await _showOngoingNotification(ongoing.last);
    }

    setState(() {
      _fileReady = true;
    });
  }

  Future<void> _saveNotes() async {
    await _jsonFile.writeAsString(
      json.encode(_notes.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _clearNotes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notes'),
        content: const Text(
          'Are you sure you want to delete all notes? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _notes.clear();
      });
      await _saveNotes();
      await _cancelOngoingNotification();
      _notificationTimer?.cancel();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All notes cleared')));
    }
  }

  void _toggleView() {
    setState(() {
      _isGridView = !_isGridView;
    });
  }

  void _cycleTheme() {
    final currentIndex = ThemeMode.values.indexOf(widget.themeMode);
    final nextIndex = (currentIndex + 1) % ThemeMode.values.length;
    widget.onThemeChanged(ThemeMode.values[nextIndex]);
  }

  String _getThemeLabel() {
    switch (widget.themeMode) {
      case ThemeMode.light:
        return 'Theme: Light';
      case ThemeMode.dark:
        return 'Theme: Dark';
      case ThemeMode.system:
        return 'Theme: System';
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<String> _getAddressFromLatLng(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.country,
        ].where((s) => s != null && s.trim().isNotEmpty).toList();
        return parts.join(', ');
      }
    } catch (_) {}
    return 'Unknown location';
  }

  Future<void> _showOngoingNotification(Note note) async {
    final duration = formatDuration(note.startTime, null);
    final body = duration;

    final androidDetails = AndroidNotificationDetails(
      notificationChannelId,
      notificationChannelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false, // Disable sound for silent updates
      styleInformation: const DefaultStyleInformation(true, true),
    );

    final details = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(
      ongoingNotificationId,
      'Timer running',
      body,
      details,
    );
  }

  Future<void> _cancelOngoingNotification() async {
    await notificationsPlugin.cancel(ongoingNotificationId);
  }

  Future<void> _startNote() async {
    try {
      bool? notificationGranted;
      final androidPlugin = notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (Platform.isAndroid) {
        notificationGranted = await androidPlugin
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        notificationGranted = await notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }

      if (notificationGranted != true) {
        throw Exception('Notification permission denied.');
      }

      final pos = await _determinePosition();
      final address = await _getAddressFromLatLng(pos.latitude, pos.longitude);
      final now = DateTime.now().toIso8601String();
      final note = Note(
        id: now,
        startTime: now,
        endTime: null,
        address: address,
        lat: pos.latitude,
        lng: pos.longitude,
      );

      setState(() {
        _notes.add(note);
      });
      await _saveNotes();
      final androidDetails = AndroidNotificationDetails(
        'start_channel',
        'Note Start',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );

      final details = NotificationDetails(android: androidDetails);
      await notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // unique ID
        'Note Started',
        'Tracking started at $address',
        details,
      );
      await _showOngoingNotification(note);
      if (!_notificationTimer!.isActive) {
        _notificationTimer = Timer.periodic(const Duration(seconds: 1), (
          timer,
        ) {
          final ongoing = _notes.where((n) => n.endTime == null).toList();
          if (ongoing.isNotEmpty) {
            _showOngoingNotification(ongoing.last);
          } else {
            timer.cancel();
          }
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Started note')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
    }
  }

  Future<void> _endNoteAtIndex(int index) async {
    final nowIso = DateTime.now().toIso8601String();
    setState(() {
      _notes[index].endTime = nowIso;
    });
    await _saveNotes();
    final stillOngoing = _notes.any((n) => n.endTime == null);
    if (!stillOngoing) {
      await _cancelOngoingNotification();
      _notificationTimer?.cancel();
    } else {
      final next = _notes.firstWhere((n) => n.endTime == null);
      await _showOngoingNotification(next);
    }
  }

  String _formatIso(String iso) {
    try {
      return DateTime.parse(iso).toLocal().toString().split('.').first;
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_fileReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Timer Notes'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle_view') {
                _toggleView();
              } else if (value == 'cycle_theme') {
                _cycleTheme();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_view',
                child: Text(
                  _isGridView ? 'Switch to List View' : 'Switch to Grid View',
                ),
              ),
              PopupMenuItem(
                value: 'cycle_theme',
                child: Text(_getThemeLabel()),
              ),
            ],
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All Notes',
            onPressed: _clearNotes,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Report',
            onPressed: _copyReportToClipboard,
          ),
        ],
      ),
      body: _notes.isEmpty
          ? const Center(child: Text('No notes yet'))
          : _isGridView
          ? GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: _notes.length,
              itemBuilder: (context, idx) {
                final note = _notes[idx];
                return _buildNoteCard(note, idx);
              },
            )
          : ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, idx) {
                final note = _notes[idx];
                return _buildNoteCard(note, idx);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNote,
        child: const Icon(Icons.gps_fixed),
      ),
    );
  }

  Widget _buildNoteCard(Note note, int index) {
    final ongoing = note.endTime == null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openNoteDetail(note, index),
        onLongPress: ongoing
            ? null
            : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Note'),
                    content: const Text(
                      'Are you sure you want to delete this note?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  setState(() {
                    _notes.removeAt(index);
                  });
                  await _saveNotes();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Note deleted')));
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Start: ${_formatIso(note.startTime)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'End: ${ongoing ? 'Ongoing' : _formatIso(note.endTime!)}',
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Duration: ${formatDuration(note.startTime, note.endTime)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Address: ${note.address}',
                style: const TextStyle(fontSize: 12),
                maxLines: _isGridView ? 2 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (ongoing) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.timelapse, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Text(
                      'Running',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openNoteDetail(Note note, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailPage(
          note: note,
          onEnd: () async {
            await _endNoteAtIndex(index);
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

class NoteDetailPage extends StatefulWidget {
  final Note note;
  final Future<void> Function() onEnd;

  const NoteDetailPage({super.key, required this.note, required this.onEnd});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.note.endTime == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatIso(String iso) {
    try {
      return DateTime.parse(iso).toLocal().toString().split('.').first;
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ongoing = widget.note.endTime == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Note Details'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start: ${_formatIso(widget.note.startTime)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              'End: ${ongoing ? 'Ongoing' : _formatIso(widget.note.endTime!)}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              'Duration: ${formatDuration(widget.note.startTime, widget.note.endTime)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Address: ${widget.note.address}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Spacer(),
            if (ongoing)
              ElevatedButton.icon(
                onPressed: () async {
                  await widget.onEnd();
                },
                icon: const Icon(Icons.stop),
                label: const Text('End Timer'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
