import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Configurable database URL (raw events.json URL from user's future repo)
  String _databaseUrl = 'https://raw.githubusercontent.com/username/repo/main/events.json';
  
  List<Article> _articles = [];
  bool _isLoading = false;
  String _statusMessage = 'SYNCHRONIZING REQUIRED';
  Color _statusColor = const Color(0xFF00c8ff);

  @override
  void initState() {
    super.key;
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'ESTABLISHING SECURE LINK...';
      _statusColor = const Color(0xFF00c8ff);
    });

    try {
      final response = await http.get(Uri.parse(_databaseUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Article> parsedArticles = data.map((json) => Article.fromJson(json)).toList();

        setState(() {
          _articles = parsedArticles;
          _isLoading = false;
          _statusMessage = _hasActiveAnomaly() ? 'ACTIVE ANOMALY DETECTED' : 'SCANNER STABLE';
          _statusColor = _hasActiveAnomaly() ? const Color(0xFFff2a6d) : const Color(0xFF02ff77);
        });

        // Trigger notifications rescheduling
        await NotificationService().rescheduleAlarms(parsedArticles);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Portal database synced. Alarms updated successfully."),
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
        _statusMessage = 'LINK ERROR - SYNCS FAILED';
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

  void _showUrlConfigDialog() {
    final controller = TextEditingController(text: _databaseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0d141e),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF00c8ff), width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text(
          "CONDUIT_SOURCE",
          style: TextStyle(
            color: Color(0xFF00c8ff),
            fontFamily: 'Orbitron',
            letterSpacing: 1.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Input raw events.json URL below to synchronize local database:",
              style: TextStyle(color: Color(0xFF94a3b8), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF475569)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00c8ff)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Color(0xFF94a3b8), fontFamily: 'Orbitron')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00c8ff).withOpacity(0.15),
              side: const BorderSide(color: Color(0xFF00c8ff)),
            ),
            onPressed: () {
              setState(() {
                _databaseUrl = controller.text;
              });
              Navigator.pop(context);
              _fetchEvents();
            },
            child: const Text("SAVE & SYNC", style: TextStyle(color: Color(0xFF00c8ff), fontFamily: 'Orbitron')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF080b11),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0d141e),
          elevation: 0,
          shape: const BorderSide(color: Color(0style: BorderStyle.none), width: 0),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "INGRESS // MONITORS",
                style: TextStyle(
                  color: Color(0xFF00c8ff),
                  fontFamily: 'Orbitron',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _statusColor.withOpacity(0.8),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusColor,
                      fontFamily: 'Orbitron',
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xFF00c8ff)),
              onPressed: _showUrlConfigDialog,
            ),
            IconButton(
              icon: const Icon(Icons.sync, color: Color(0xFF02ff77)),
              onPressed: _isLoading ? null : _fetchEvents,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF00c8ff),
            labelColor: Color(0xFF00c8ff),
            unselectedLabelColor: Color(0xFF475569),
            labelStyle: TextStyle(fontFamily: 'Orbitron', fontSize: 11, letterSpacing: 1.0),
            tabs: [
              Tab(text: "ACTIVE_NOW"),
              Tab(text: "SCHEDULED"),
              Tab(text: "ARCHIVED"),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisSize.center,
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
          margin: const EdgeInsets.bottom(16),
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
                  mainAxisAlignment: MainAxisAlignment.between,
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, py: 3),
                      decoration: BoxDecoration(
                        border: Border.solid(
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
                        mainAxisAlignment: MainAxisAlignment.between,
                        children: [
                          const Text("START:", style: TextStyle(color: Color(0xFF94a3b8), fontSize: 10, fontFamily: 'Orbitron')),
                          Text(startStr, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.between,
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
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
