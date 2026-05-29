import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../../constants/app_constants.dart';
import '../../providers/providers.dart';
import '../../services/api_service.dart';

// ─── WebSocket Service ────────────────────────────────────────────────────────

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _locationController = StreamController<Map<String, dynamic>>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get locationStream => _locationController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  // Base URL — replace with your server
  static const _wsBase = 'ws://10.0.2.2:8000/api/v1/ws';

  /// Client connects to receive agent location updates for a task
  Future<void> connectToTask(String taskId, String accessToken) async {
    disconnect();
    final uri = Uri.parse('$_wsBase/track/$taskId?token=$accessToken');
    try {
      _channel = IOWebSocketChannel.connect(uri);
      _subscription = _channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            final type = data['type'] as String?;
            if (type == 'location_update') {
              _locationController.add(data);
            } else {
              _eventController.add(data);
            }
          } catch (_) {}
        },
        onError: (e) => print('[WS] Error: $e'),
        onDone: () => print('[WS] Task tracking disconnected'),
      );
    } catch (e) {
      print('[WS] Connect failed: $e');
    }
  }

  /// Agent connects to send location updates
  Future<void> connectAsAgent(String accessToken) async {
    disconnect();
    final uri = Uri.parse('$_wsBase/location?token=$accessToken');
    try {
      _channel = IOWebSocketChannel.connect(uri);
    } catch (e) {
      print('[WS] Agent connect failed: $e');
    }
  }

  /// Agent sends their current GPS position
  void sendLocation(String taskId, double lat, double lng) {
    _channel?.sink.add(jsonEncode({
      'task_id': taskId,
      'lat': lat,
      'lng': lng,
    }));
  }

  /// Send ping to keep connection alive
  void ping() {
    _channel?.sink.add('ping');
  }

  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _locationController.close();
    _eventController.close();
  }
}

// Global singleton
final wsService = WebSocketService();

// ─── Riverpod Providers ────────────────────────────────────────────────────────

final agentLocationProvider = StreamProvider.family<LatLng?, String>((ref, taskId) {
  return wsService.locationStream
      .where((data) => data['task_id'] == taskId)
      .map((data) => LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          ));
});

// ─── Live Tracking Screen (Client) ────────────────────────────────────────────

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String taskId;
  const LiveTrackingScreen({super.key, required this.taskId});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _agentLocation;
  LatLng? _taskLocation;
  Timer? _pingTimer;
  bool _isConnected = false;
  String? _taskStatus;
  List<LatLng> _routePoints = [];

  // Default to Lagos center before task location loads
  static const _lagosCenter = LatLng(6.5244, 3.3792);

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final token = await ApiService.getAccessToken();
    if (token == null) return;

    await wsService.connectToTask(widget.taskId, token);

    // Listen to location updates
    wsService.locationStream.listen((data) {
      if (!mounted) return;
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final agentLatLng = LatLng(lat, lng);

      setState(() {
        _agentLocation = agentLatLng;
        _isConnected = true;
        _routePoints.add(agentLatLng);
        _updateMarkers();
        _updatePolyline();
      });

      // Animate camera to follow agent
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(agentLatLng),
      );
    });

    // Listen to task events
    wsService.eventStream.listen((data) {
      if (!mounted) return;
      final type = data['type'] as String?;
      setState(() => _taskStatus = type);

      if (type == 'task_completed') {
        _showCompletionDialog();
      }
    });

    // Load task location
    final taskData = await apiService.getTask(widget.taskId);
    if (mounted) {
      setState(() {
        _taskLocation = LatLng(
          (taskData['pickup_lat'] as num).toDouble(),
          (taskData['pickup_lng'] as num).toDouble(),
        );
        _updateMarkers();
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_taskLocation ?? _lagosCenter),
      );
    }

    // Keep WebSocket alive with periodic pings
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      wsService.ping();
    });
  }

  void _updateMarkers() {
    _markers.clear();

    if (_agentLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('agent'),
        position: _agentLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Agent'),
      ));
    }

    if (_taskLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('task'),
        position: _taskLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Pickup location'),
      ));
    }
  }

  void _updatePolyline() {
    if (_routePoints.length < 2) return;
    _polylines.clear();
    _polylines.add(Polyline(
      polylineId: const PolylineId('agent_route'),
      points: List.from(_routePoints),
      color: AppColors.secondary,
      width: 4,
    ));
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Task Completed! 🎉'),
        content: const Text(
          'Your agent has completed the task. '
          'Please confirm and release payment.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/client/task/${widget.taskId}/track');
            },
            child: const Text('Confirm Completion'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    wsService.disconnect();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Live Tracking', style: AppTextStyles.h2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/client/home'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected ? AppColors.secondary : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Live' : 'Connecting...',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _isConnected ? AppColors.secondary : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live map
          Expanded(
            flex: 3,
            child: GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                if (_taskLocation != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_taskLocation!, 15),
                  );
                }
              },
              initialCameraPosition: CameraPosition(
                target: _taskLocation ?? _lagosCenter,
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Status panel
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Agent location info
                  if (_agentLocation != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.08),
                        borderRadius: AppRadius.cardRadius,
                        border: Border.all(
                            color: AppColors.secondary.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: AppColors.secondary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Agent location updated',
                                    style: AppTextStyles.labelLarge
                                        .copyWith(color: AppColors.secondary)),
                                Text(
                                  '${_agentLocation!.latitude.toStringAsFixed(4)}, '
                                  '${_agentLocation!.longitude.toStringAsFixed(4)}',
                                  style: AppTextStyles.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_agentLocation == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.warning),
                          ),
                          const SizedBox(width: 10),
                          Text('Waiting for agent location...',
                              style: AppTextStyles.labelMedium
                                  .copyWith(color: AppColors.warning)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),
                  Text('Task status', style: AppTextStyles.h3),
                  const SizedBox(height: 8),

                  _StatusTimeline(taskId: widget.taskId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Agent Live Location Sender ───────────────────────────────────────────────

class AgentLocationService {
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStream;
  final String taskId;
  final String accessToken;

  AgentLocationService({required this.taskId, required this.accessToken});

  Future<void> start() async {
    // Connect WebSocket
    await wsService.connectAsAgent(accessToken);

    // Request location permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    // Stream GPS position every 5 seconds
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Only update if moved 10 meters
      ),
    ).listen((position) {
      wsService.sendLocation(taskId, position.latitude, position.longitude);
    });
  }

  void stop() {
    _locationTimer?.cancel();
    _positionStream?.cancel();
    wsService.disconnect();
  }
}

// ─── Status Timeline Widget ───────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final String taskId;
  const _StatusTimeline({required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TimelineItem(
          label: 'Agent assigned',
          subtitle: 'Agent is on the way',
          isDone: true,
          color: AppColors.secondary,
        ),
        _TimelineItem(
          label: 'Task in progress',
          subtitle: 'Agent is working on your task',
          isDone: false,
          color: AppColors.warning,
        ),
        _TimelineItem(
          label: 'Completion proof',
          subtitle: 'Agent will submit photos when done',
          isDone: false,
          color: AppColors.primary,
          isLast: true,
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isDone;
  final Color color;
  final bool isLast;

  const _TimelineItem({
    required this.label,
    required this.subtitle,
    required this.isDone,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isDone ? color : AppColors.border,
                shape: BoxShape.circle,
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isDone ? color.withOpacity(0.3) : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTextStyles.labelLarge.copyWith(
                      color: isDone ? AppColors.textPrimary : AppColors.textTertiary)),
              Text(subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: isDone ? AppColors.textSecondary : AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}
