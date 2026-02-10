import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const FitnessTrackerApp());
}

class FitnessTrackerApp extends StatelessWidget {
  const FitnessTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fitness Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const FitnessDashboard(),
    );
  }
}

class FitnessDashboard extends StatefulWidget {
  const FitnessDashboard({super.key});

  @override
  State<FitnessDashboard> createState() => _FitnessDashboardState();
}

class _FitnessDashboardState extends State<FitnessDashboard> {
  static const double _metersPerStep = 0.78;
  static const double _caloriesPerStep = 0.04;
  static const int _chartSamples = 18;

  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<PedestrianStatus>? _statusSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  int? _bootStepBaseline;
  int _steps = 0;
  double _motionLevel = 0;
  String _movementStatus = 'unknown';
  String? _errorText;
  DateTime _lastUpdated = DateTime.now();
  final List<_StepSnapshot> _history = <_StepSnapshot>[];

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    final PermissionStatus permission = await Permission.activityRecognition
        .request();
    if (!mounted) return;

    if (!permission.isGranted) {
      setState(() {
        _errorText =
            'Activity recognition permission is required for step tracking.';
      });
      return;
    }

    _stepSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStreamError,
    );
    _statusSubscription = Pedometer.pedestrianStatusStream.listen(
      _onPedestrianStatus,
      onError: _onStreamError,
    );
    _accelSubscription = accelerometerEventStream().listen(
      _onAccelerometerEvent,
      onError: _onStreamError,
    );
  }

  void _onStepCount(StepCount stepCount) {
    final int sensorSteps = stepCount.steps;
    final int baseline = _bootStepBaseline ?? sensorSteps;
    final int computedSteps = max(0, sensorSteps - baseline);

    setState(() {
      _bootStepBaseline ??= sensorSteps;
      _steps = computedSteps;
      _lastUpdated = DateTime.now();
      _history.add(_StepSnapshot(timestamp: _lastUpdated, steps: _steps));
      if (_history.length > _chartSamples) {
        _history.removeAt(0);
      }
      _errorText = null;
    });
  }

  void _onPedestrianStatus(PedestrianStatus status) {
    setState(() {
      _movementStatus = status.status;
    });
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final double magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    setState(() {
      _motionLevel = magnitude;
    });
  }

  void _onStreamError(dynamic error) {
    setState(() {
      _errorText = 'Sensor error: $error';
    });
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    _statusSubscription?.cancel();
    _accelSubscription?.cancel();
    super.dispose();
  }

  double get _distanceKm => (_steps * _metersPerStep) / 1000;

  double get _calories => _steps * _caloriesPerStep;

  String _formatTime(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fitness Tracker')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_errorText != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _MetricCard(
                    icon: Icons.directions_walk,
                    label: 'Steps',
                    value: _steps.toString(),
                  ),
                  _MetricCard(
                    icon: Icons.route,
                    label: 'Distance',
                    value: '${_distanceKm.toStringAsFixed(2)} km',
                  ),
                  _MetricCard(
                    icon: Icons.local_fire_department,
                    label: 'Calories',
                    value: '${_calories.toStringAsFixed(0)} kcal',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Real-time Activity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Status: ${_movementStatus.toUpperCase()}'),
                      Text(
                        'Motion level: ${_motionLevel.toStringAsFixed(2)} m/s^2',
                      ),
                      Text('Last update: ${_formatTime(_lastUpdated)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Step Trend',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: LineChart(
                            LineChartData(
                              minY: 0,
                              gridData: const FlGridData(show: true),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 42,
                                    interval: max(
                                      1,
                                      (_steps / 4).ceilToDouble(),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 5,
                                    getTitlesWidget:
                                        (double value, TitleMeta meta) {
                                          final int index = value.toInt();
                                          if (index < 0 ||
                                              index >= _history.length) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              _formatTime(
                                                _history[index].timestamp,
                                              ),
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ),
                              lineTouchData: const LineTouchData(enabled: true),
                              borderData: FlBorderData(show: true),
                              lineBarsData: <LineChartBarData>[
                                LineChartBarData(
                                  isCurved: true,
                                  color: Colors.green,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: false),
                                  spots: _history.isEmpty
                                      ? const <FlSpot>[FlSpot(0, 0)]
                                      : _history
                                            .asMap()
                                            .entries
                                            .map(
                                              (
                                                MapEntry<int, _StepSnapshot>
                                                entry,
                                              ) => FlSpot(
                                                entry.key.toDouble(),
                                                entry.value.steps.toDouble(),
                                              ),
                                            )
                                            .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 44) / 2,
      child: Card(
        color: colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colorScheme.onSecondaryContainer),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: colorScheme.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepSnapshot {
  const _StepSnapshot({required this.timestamp, required this.steps});

  final DateTime timestamp;
  final int steps;
}
