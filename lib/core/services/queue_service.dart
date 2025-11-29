import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/queue_entry.dart';

class QueueService {
  static final QueueService _instance = QueueService._internal();
  factory QueueService() => _instance;
  QueueService._internal();

  final _queueController = StreamController<QueueEntry?>.broadcast();
  Stream<QueueEntry?> get queueStream => _queueController.stream;

  QueueEntry? _currentQueue;
  Timer? _simulationTimer;

  /// Get current active queue entry
  QueueEntry? get currentQueue => _currentQueue;

  /// Join a queue at a clinic
  Future<QueueEntry> joinQueue({
    required String clinicId,
    required String clinicName,
    required String userId,
  }) async {
    // Cancel existing queue if any
    await cancelQueue();

    // Create new queue entry with random initial position (2-10)
    final random = Random();
    final position = random.nextInt(9) + 2; // 2 to 10
    final waitTime = position * 7; // ~7 minutes per person

    final queueEntry = QueueEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      clinicId: clinicId,
      clinicName: clinicName,
      userId: userId,
      joinedAt: DateTime.now(),
      position: position,
      estimatedWaitMinutes: waitTime,
      status: QueueStatus.confirmed,
      updates: [
        QueueUpdate(
          message: 'Successfully joined the queue',
          timestamp: DateTime.now(),
        ),
      ],
    );

    _currentQueue = queueEntry;
    await _saveQueue(queueEntry);
    _queueController.add(queueEntry);

    // Start simulation
    _startQueueSimulation();

    return queueEntry;
  }

  /// Cancel current queue
  Future<void> cancelQueue() async {
    if (_currentQueue != null) {
      _currentQueue = null;
      _simulationTimer?.cancel();
      await _clearSavedQueue();
      _queueController.add(null);
    }
  }

  /// Load saved queue from local storage
  Future<void> loadSavedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString('current_queue');
    
    if (queueJson != null) {
      try {
        final Map<String, dynamic> json = jsonDecode(queueJson);
        _currentQueue = QueueEntry.fromJson(json);
        _queueController.add(_currentQueue);
        
        // Resume simulation if still waiting
        if (_currentQueue!.status == QueueStatus.confirmed ||
            _currentQueue!.status == QueueStatus.waiting) {
          _startQueueSimulation();
        }
      } catch (e) {
        // Invalid data, clear it
        await _clearSavedQueue();
      }
    }
  }

  /// Save queue to local storage
  Future<void> _saveQueue(QueueEntry queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_queue', jsonEncode(queue.toJson()));
  }

  /// Clear saved queue
  Future<void> _clearSavedQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_queue');
  }

  /// Simulate queue progression (moves forward every 2-4 minutes)
  void _startQueueSimulation() {
    _simulationTimer?.cancel();
    
    // Simulate queue movement every 30 seconds (for demo purposes)
    // In production, you'd connect to real backend updates
    _simulationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_currentQueue == null) {
        timer.cancel();
        return;
      }

      // Don't update if already called or completed
      if (_currentQueue!.status == QueueStatus.called ||
          _currentQueue!.status == QueueStatus.completed ||
          _currentQueue!.status == QueueStatus.cancelled) {
        timer.cancel();
        return;
      }

      // Move forward in queue
      if (_currentQueue!.position > 1) {
        final random = Random();
        final shouldUpdate = random.nextBool(); // 50% chance to move forward
        
        if (shouldUpdate) {
          final newPosition = _currentQueue!.position - 1;
          final newWaitTime = newPosition * 7;
          
          final updates = List<QueueUpdate>.from(_currentQueue!.updates);
          
          // Add random clinic updates
          final clinicUpdates = [
            'Patient ahead completed their visit',
            'Queue moving smoothly',
            'Clinic is running on schedule',
            'Doctor available soon',
          ];
          
          if (random.nextInt(3) == 0) { // 33% chance for clinic update
            updates.insert(0, QueueUpdate(
              message: clinicUpdates[random.nextInt(clinicUpdates.length)],
              timestamp: DateTime.now(),
            ));
          }
          
          updates.insert(0, QueueUpdate(
            message: 'Your position updated to $newPosition${_getOrdinalSuffix(newPosition)}',
            timestamp: DateTime.now(),
          ));

          _currentQueue = _currentQueue!.copyWith(
            position: newPosition,
            estimatedWaitMinutes: newWaitTime,
            updates: updates,
          );

          _saveQueue(_currentQueue!);
          _queueController.add(_currentQueue);
        }
      } else {
        // You're next! Change status to called
        final updates = List<QueueUpdate>.from(_currentQueue!.updates);
        updates.insert(0, QueueUpdate(
          message: 'You are next! Please proceed to the clinic',
          timestamp: DateTime.now(),
        ));

        _currentQueue = _currentQueue!.copyWith(
          status: QueueStatus.called,
          updates: updates,
        );

        _saveQueue(_currentQueue!);
        _queueController.add(_currentQueue);
        timer.cancel();
      }
    });
  }

  String _getOrdinalSuffix(int number) {
    if (number >= 11 && number <= 13) {
      return 'th';
    }
    switch (number % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  void dispose() {
    _simulationTimer?.cancel();
    _queueController.close();
  }
}
