import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/event.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Configurable database URL (raw events.json URL from user's repository)
  String _databaseUrl = 'https://raw.githubusercontent.com/operationdelta-ghdev/operationdelta/main/events.json';
  
  List<Article> _articles = [];
  bool _isLoading = false;
  String _lastUpdated = 'SYNCHRONIZING REQUIRED';
  Color _statusColor = const Color(0xFF00c8ff);

  // Notification toggles
  bool _notifyEventStart = true;
  bool _notifyOneDayBeforeStart = true;
  bool _notifyOneDayBeforeEnd = true;
  bool _notifyEventEnd = true;

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifyEventStart = prefs.getBool('notify_event_start') ?? true;
      _notifyOneDayBeforeStart = prefs.getBool('notify_one_day_start') ?? true;
      _notifyOneDayBeforeEnd = prefs.getBool('notify_one_day_end') ?? true;
      _notifyEventEnd = prefs.getBool('notify_event_end') ?? true;
    });
  }

  Future<void> _saveNotificationSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    // Automatically update scheduled notifications
    try {
      await NotificationService().rescheduleAlarms(_articles);
    } catch (e) {
      debugPrint("Error rescheduling notifications after setting change: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _fetchEvents();
    // Request runtime permissions after first frame, when an Activity is active.
    // This is required for the system notification dialog to appear on Android 13+.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService().requestPermissions();
      } catch (e) {
        debugPrint('Error requesting notification permissions: $e');
      }
    });
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _lastUpdated = 'ESTABLISHING SECURE LINK...';
      _statusColor = const Color(0xFF00c8ff);
    });

    try {
      final response = await http.get(Uri.parse(_databaseUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Article> parsedArticles = data.map((json) => Article.fromJson(json)).toList();

        int latestTimestamp = 0;
        for (var art in parsedArticles) {
          if (art.publishedAt > latestTimestamp) {
            latestTimestamp = art.publishedAt;
          }
        }
        
        String formattedLastUpdated = 'UNKNOWN';
        if (latestTimestamp > 0) {
          final lastUpdatedDate = DateTime.fromMillisecondsSinceEpoch(latestTimestamp);
          final DateFormat formatter = DateFormat('yyyy-MM-dd');
          formattedLastUpdated = formatter.format(lastUpdatedDate.toLocal());
        }

        setState(() {
          _articles = parsedArticles;
          _isLoading = false;
          _lastUpdated = 'UPDATED: $formattedLastUpdated';
          _statusColor = _hasActiveAnomaly() ? const Color(0xFFff2a6d) : const Color(0xFF02ff77);
        });

        // Trigger notifications rescheduling
        try {
          await NotificationService().rescheduleAlarms(parsedArticles);
        } catch (e) {
          debugPrint("Error rescheduling notifications after fetch: $e");
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Portal database synced. Scheduled notifications updated successfully."),
              backgroundColor: Color(0xFF02ff77),
            ),
          );
        }
      } else {
        throw Exception("Server responded with code: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _lastUpdated = 'LINK ERROR - SYNCS FAILED';
        _statusColor = const Color(0xFFff2a6d);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync Failed: $e"),
            backgroundColor: const Color(0xFFff2a6d),
          ),
        );
      }
    }
  }

  bool _hasActiveAnomaly() {
    final DateTime now = DateTime.now();
    for (var art in _articles) {
      for (var ev in art.events) {
        if (ev.getStatus(now) == 'active') {
          return true;
        }
      }
    }
    return false;
  }

  // Split and filter all events by state
  List<Map<String, dynamic>> _getFilteredEvents(String stateFilter) {
    final List<Map<String, dynamic>> list = [];
    final DateTime now = DateTime.now();

    for (var art in _articles) {
      for (var ev in art.events) {
        if (ev.getStatus(now) == stateFilter) {
          list.add({
            'article': art,
            'event': ev,
          });
        }
      }
    }
    
    // Sort:
    if (stateFilter == 'active') {
      list.sort((a, b) => (a['event'] as IngressEvent).endTime.compareTo((b['event'] as IngressEvent).endTime));
    } else if (stateFilter == 'upcoming') {
      list.sort((a, b) => (a['event'] as IngressEvent).startTime.compareTo((b['event'] as IngressEvent).startTime));
    } else {
      list.sort((a, b) => (b['event'] as IngressEvent).endTime.compareTo((a['event'] as IngressEvent).endTime));
    }
    return list;
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0d141e),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF00c8ff), width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              title: const Text(
                "Notification Options",
                style: TextStyle(
                  color: Color(0xFF00c8ff),
                  fontFamily: 'Orbitron',
                  letterSpacing: 1.5,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("Event Start", style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF02ff77),
                    value: _notifyEventStart,
                    onChanged: (bool value) {
                      setState(() {
                        _notifyEventStart = value;
                      });
                      setDialogState(() {
                        _notifyEventStart = value;
                      });
                      _saveNotificationSetting('notify_event_start', value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text("24h Notice (Start)", style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF02ff77),
                    value: _notifyOneDayBeforeStart,
                    onChanged: (bool value) {
                      setState(() {
                        _notifyOneDayBeforeStart = value;
                      });
                      setDialogState(() {
                        _notifyOneDayBeforeStart = value;
                      });
                      _saveNotificationSetting('notify_one_day_start', value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text("24h Notice (End)", style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF02ff77),
                    value: _notifyOneDayBeforeEnd,
                    onChanged: (bool value) {
                      setState(() {
                        _notifyOneDayBeforeEnd = value;
                      });
                      setDialogState(() {
                        _notifyOneDayBeforeEnd = value;
                      });
                      _saveNotificationSetting('notify_one_day_end', value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text("Event End", style: TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: const Color(0xFF02ff77),
                    value: _notifyEventEnd,
                    onChanged: (bool value) {
                      setState(() {
                        _notifyEventEnd = value;
                      });
                      setDialogState(() {
                        _notifyEventEnd = value;
                      });
                      _saveNotificationSetting('notify_event_end', value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CLOSE", style: TextStyle(color: Color(0xFF00c8ff), fontFamily: 'Orbitron')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "OPERATION_DELTA",
                style: TextStyle(
                  color: Color(0xFFff2a6d),
                  fontFamily: 'Orbitron',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _lastUpdated,
                style: TextStyle(
                  color: _statusColor,
                  fontFamily: 'Orbitron',
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xFF00c8ff)),
              onPressed: _showSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.sync, color: Color(0xFF02ff77)),
              onPressed: _isLoading ? null : _fetchEvents,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildTimelineView(),
            TabBar(
              indicatorColor: const Color(0xFF02ff77),
              labelColor: const Color(0xFF02ff77),
              unselectedLabelColor: const Color(0xFF475569),
              labelStyle: const TextStyle(fontFamily: 'Orbitron', fontSize: 11, letterSpacing: 1.0),
              tabs: const [
                Tab(text: "ACTIVE NOW"),
                Tab(text: "SCHEDULED"),
                Tab(text: "ARCHIVED"),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFF00c8ff),
                          ),
                          SizedBox(height: 16),
                          Text(
                            "SCANNING NEURAL INTERFACE...",
                            style: TextStyle(
                              color: Color(0xFF00c8ff),
                              fontFamily: 'Orbitron',
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      children: [
                        _buildEventList('active'),
                        _buildEventList('upcoming'),
                        _buildEventList('past'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList(String stateFilter) {
    final events = _getFilteredEvents(stateFilter);

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: const Color(0xFF475569), size: 48),
            const SizedBox(height: 12),
            const Text(
              "NO RECORDS DETECTED IN THIS VECTOR.",
              style: TextStyle(
                color: Color(0xFF94a3b8),
                fontSize: 12,
                fontFamily: 'Orbitron',
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final item = events[index];
        final Article article = item['article'];
        final IngressEvent event = item['event'];
        
        final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm');
        
        // Formatted strings
        String startStr = event.timingType == 'local' 
            ? "${formatter.format(event.startTime.toUtc())} LOCAL" // display direct raw UTC fields as local clock
            : formatter.format(event.startTime.toLocal()); // convert absolute
            
        String endStr = event.timingType == 'local'
            ? "${formatter.format(event.endTime.toUtc())} LOCAL"
            : formatter.format(event.endTime.toLocal());

        final isAccentEnlightened = stateFilter == 'active';
        final accentColor = isAccentEnlightened ? const Color(0xFF02ff77) : const Color(0xFF00c8ff);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          color: const Color(0xFF0d141e).withOpacity(0.85),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: stateFilter == 'past' ? const Color(0xFF475569) : accentColor.withOpacity(0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        event.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Orbitron',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: event.timingType == 'local' ? const Color(0xFF02ff77) : const Color(0xFF00c8ff),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(2),
                        color: event.timingType == 'local' 
                            ? const Color(0xFF02ff77).withOpacity(0.1) 
                            : const Color(0xFF00c8ff).withOpacity(0.1),
                      ),
                      child: Text(
                        event.timingType.toUpperCase(),
                        style: TextStyle(
                          color: event.timingType == 'local' ? const Color(0xFF02ff77) : const Color(0xFF00c8ff),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Orbitron',
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                if (stateFilter == 'active' || stateFilter == 'upcoming') ...[
                  const SizedBox(height: 12),
                  CountdownWidget(
                    targetTime: stateFilter == 'active' ? event.getAdjustedEnd(DateTime.now()) : event.getAdjustedStart(DateTime.now()),
                    prefix: stateFilter == 'active' ? 'REMAINING: ' : 'STARTS IN: ',
                    finishedText: stateFilter == 'active' ? 'MUTATION COMPLETE' : 'MUTATION ACTIVE',
                    accentColor: accentColor,
                    onFinished: () {
                      setState(() {});
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    border: Border(
                      left: BorderSide(
                        color: stateFilter == 'past' ? const Color(0xFF475569) : accentColor,
                        width: 2.0,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("START:", style: TextStyle(color: Color(0xFF94a3b8), fontSize: 10, fontFamily: 'Orbitron')),
                          Text(startStr, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("END:", style: TextStyle(color: Color(0xFF94a3b8), fontSize: 10, fontFamily: 'Orbitron')),
                          Text(endStr, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "GAMEPLAY_MUTATIONS:",
                  style: TextStyle(
                    color: Color(0xFF94a3b8),
                    fontSize: 9,
                    fontFamily: 'Orbitron',
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                ...event.changes.map((mutation) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "> ",
                        style: TextStyle(
                          color: stateFilter == 'past' ? const Color(0xFF475569) : accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          mutation,
                          style: const TextStyle(
                            color: Color(0xFFe2e8f0),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                const Divider(color: Color(0xFF475569), height: 24, thickness: 0.5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "SOURCE_INTEL:",
                      style: TextStyle(color: Color(0xFF475569), fontSize: 8, fontFamily: 'Orbitron'),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse(article.url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not launch source URL: ${article.url}')),
                              );
                            }
                          }
                        },
                        child: Text(
                          article.title,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFF00c8ff),
                            fontSize: 9,
                            decoration: TextDecoration.underline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Timeline view generator
  Widget _buildTimelineView() {
    final now = DateTime.now();
    final currentWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7));
    final calStart = currentWeekStart.subtract(const Duration(days: 7));
    final calEnd = calStart.add(const Duration(days: 28));

    final calStartOnly = DateTime(calStart.year, calStart.month, calStart.day);
    final calEndOnly = DateTime(calEnd.year, calEnd.month, calEnd.day);

    List<Map<String, dynamic>> allEventsList = [];
    for (var article in _articles) {
      for (var event in article.events) {
        allEventsList.add({
          'article': article,
          'event': event,
        });
      }
    }

    final timelineEvents = allEventsList.where((item) {
      final IngressEvent event = item['event'];
      final DateTime eventStart = DateTime(event.getAdjustedStart(now).year, event.getAdjustedStart(now).month, event.getAdjustedStart(now).day);
      final DateTime eventEnd = DateTime(event.getAdjustedEnd(now).year, event.getAdjustedEnd(now).month, event.getAdjustedEnd(now).day);
      return eventStart.isBefore(calEndOnly) && eventEnd.isAfter(calStartOnly);
    }).toList();

    const double dayWidth = 32.0;
    const double totalWidth = dayWidth * 28;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0d141e),
        border: Border.all(color: const Color(0xFF475569).withOpacity(0.3), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TIMELINE VIEW",
                style: TextStyle(
                  color: Color(0xFF00c8ff),
                  fontFamily: 'Orbitron',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                "28-DAY VIEWING WINDOW",
                style: TextStyle(
                  color: const Color(0xFF475569),
                  fontFamily: 'Orbitron',
                  fontSize: 8,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  _buildWeeksHeader(currentWeekStart, calStart, dayWidth),
                  _buildDaysHeader(calStart, now, dayWidth),
                  const SizedBox(height: 4),
                  if (timelineEvents.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: const Text(
                        "NO ACTIVE OR SCHEDULED EVENTS IN THIS RANGE",
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontFamily: 'Orbitron',
                          fontSize: 9,
                        ),
                      ),
                    )
                  else
                    ...timelineEvents.map((item) {
                      final IngressEvent event = item['event'];
                      final Article article = item['article'];
                      return _buildTimelineRow(event, article, calStartOnly, calEndOnly, dayWidth);
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeksHeader(DateTime currentWeekStart, DateTime calStart, double dayWidth) {
    const weekLabels = ["LAST WEEK", "CURRENT WEEK", "UPCOMING WEEK +1", "UPCOMING WEEK +2"];
    final double weekWidth = dayWidth * 7;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF475569), width: 0.5)),
      ),
      child: Row(
        children: List.generate(4, (w) {
          final isCurrent = w == 1;
          final isUpcoming = w > 1;
          
          Color textColor = const Color(0xFF94a3b8);
          Color bgColor = Colors.transparent;
          if (isCurrent) {
            textColor = const Color(0xFF02ff77);
            bgColor = const Color(0xFF02ff77).withOpacity(0.05);
          } else if (isUpcoming) {
            textColor = const Color(0xFF00c8ff);
          }

          return Container(
            width: weekWidth,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                right: w < 3 ? BorderSide(color: Colors.white.withOpacity(0.05), width: 1) : BorderSide.none,
              ),
            ),
            child: Text(
              weekLabels[w],
              style: TextStyle(
                color: textColor,
                fontFamily: 'Orbitron',
                fontSize: 8,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 0.5,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDaysHeader(DateTime calStart, DateTime now, double dayWidth) {
    const dayNames = ["S", "M", "T", "W", "T", "F", "S"];
    final nowOnly = DateTime(now.year, now.month, now.day);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF475569), width: 0.5)),
      ),
      child: Row(
        children: List.generate(28, (d) {
          final dayDate = calStart.add(Duration(days: d));
          final isToday = DateTime(dayDate.year, dayDate.month, dayDate.day) == nowOnly;
          
          return Container(
            width: dayWidth,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                right: d < 27 ? BorderSide(color: Colors.white.withOpacity(0.03), width: 1) : BorderSide.none,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dayNames[dayDate.weekday % 7],
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 7, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF02ff77),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      "${dayDate.day}",
                      style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Text(
                    "${dayDate.day}",
                    style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 8),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTimelineRow(IngressEvent event, Article article, DateTime calStartOnly, DateTime calEndOnly, double dayWidth) {
    final now = DateTime.now();
    final DateTime eventStart = DateTime(event.getAdjustedStart(now).year, event.getAdjustedStart(now).month, event.getAdjustedStart(now).day);
    final DateTime eventEnd = DateTime(event.getAdjustedEnd(now).year, event.getAdjustedEnd(now).month, event.getAdjustedEnd(now).day);

    final overlapStart = eventStart.isBefore(calStartOnly) ? calStartOnly : eventStart;
    final overlapEnd = eventEnd.isAfter(calEndOnly) ? calEndOnly : eventEnd;

    final startDayIdx = overlapStart.difference(calStartOnly).inDays;
    final endDayIdx = overlapEnd.difference(calStartOnly).inDays;

    final double left = startDayIdx * dayWidth;
    final double width = (endDayIdx - startDayIdx + 1) * dayWidth;

    final state = event.getStatus(now);
    Color barColor = const Color(0xFF475569);
    if (state == 'active') {
      barColor = const Color(0xFF02ff77);
    } else if (state == 'upcoming') {
      barColor = const Color(0xFF00c8ff);
    }

    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.01), width: 1)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: left + 2,
            width: width - 4,
            top: 4,
            height: 20,
            child: Tooltip(
              message: "${event.name}\n${DateFormat('yyyy-MM-dd').format(eventStart)} to ${DateFormat('yyyy-MM-dd').format(eventEnd)}",
              child: GestureDetector(
                onTap: () {
                  int tabIndex = 2; // past
                  if (state == 'active') tabIndex = 0;
                  if (state == 'upcoming') tabIndex = 1;
                  
                  DefaultTabController.of(context).animateTo(tabIndex);
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF0d141e),
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: barColor, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      content: Text(
                        "FILTERED VIEW TO: ${event.name.toUpperCase()}",
                        style: TextStyle(
                          color: barColor,
                          fontFamily: 'Orbitron',
                          fontSize: 11,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: barColor.withOpacity(0.4),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontFamily: 'Orbitron',
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Live Countdown Badge
class CountdownWidget extends StatefulWidget {
  final DateTime targetTime;
  final String prefix;
  final String finishedText;
  final Color accentColor;
  final VoidCallback? onFinished;

  const CountdownWidget({
    super.key,
    required this.targetTime,
    required this.prefix,
    required this.finishedText,
    required this.accentColor,
    this.onFinished,
  });

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  Timer? _timer;
  late Duration _timeRemaining;

  @override
  void initState() {
    super.initState();
    _calculateTimeRemaining();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_timeRemaining.inSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          final wasPositive = _timeRemaining.inSeconds > 0;
          setState(() {
            _calculateTimeRemaining();
          });
          if (wasPositive && (_timeRemaining.isNegative || _timeRemaining.inSeconds <= 0)) {
            _timer?.cancel();
            _timer = null;
            widget.onFinished?.call();
          }
        }
      });
    }
  }

  void _calculateTimeRemaining() {
    final now = DateTime.now();
    _timeRemaining = widget.targetTime.difference(now);
  }

  @override
  void didUpdateWidget(covariant CountdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetTime != widget.targetTime) {
      _calculateTimeRemaining();
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeRemaining.isNegative || _timeRemaining.inSeconds <= 0) {
      return Text(
        widget.finishedText,
        style: TextStyle(
          color: widget.accentColor,
          fontFamily: 'Orbitron',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      );
    }

    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    List<String> parts = [];
    if (days > 0) parts.add("${days}D");
    if (days > 0 || hours > 0) parts.add("${hours}H");
    if (days > 0 || hours > 0 || minutes > 0) parts.add("${minutes.toString().padLeft(2, '0')}M");
    parts.add("${seconds.toString().padLeft(2, '0')}S");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.accentColor.withOpacity(0.1),
        border: Border.all(color: widget.accentColor, width: 1.0),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        "${widget.prefix}${parts.join(' ')}",
        style: TextStyle(
          color: widget.accentColor,
          fontFamily: 'Orbitron',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
