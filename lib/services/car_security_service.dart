import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';

class CarSecurityService {
  static final CarSecurityService _instance = CarSecurityService._internal();
  factory CarSecurityService() => _instance;
  CarSecurityService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription? _vibeSub, _locSub, _cmdSub, _trackSub;
  bool isSystemActive = false;
  String? myCarID;
  double? sLat, sLng;

  void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'car_security_channel',
        channelName: 'Hasba Security Service',
        channelDescription: 'نظام حماية السيارة يعمل في الخلفية',
        channelImportance: NotificationChannelImportance.MAX,
        priority: NotificationPriority.MAX,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: true, playSound: true),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }

  // تفعيل النظام بسرعة فائقة
  Future<void> initSecuritySystem() async {
    if (isSystemActive) return;

    initForegroundTask();
    await FlutterForegroundTask.startService(
      notificationTitle: '🛡️ نظام حماية HASBA نشط',
      notificationText: 'جاري مراقبة السيارة وحمايتها الآن...',
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    myCarID = prefs.getString('car_id');

    // جلب سريع للموقع (بدون انتظار)
    Position? p = await Geolocator.getLastKnownPosition();
    if (p == null) {
      try {
        p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5), // مهلة 5 ثواني فقط
        );
      } catch (e) {
        // إذا فشل الـ GPS، نأخذ موقعاً صفرياً مؤقتاً لتفعيل النظام فوراً
        p = Position(latitude: 0, longitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0);
      }
    }

    sLat = p.latitude; sLng = p.longitude;
    isSystemActive = true;

    _startSensors();
    _listenToCommands();
    _send('status', '🛡️ نظام الحماية نشط (استجابة سريعة)');
  }

  void _startSensors() {
    _vibeSub = accelerometerEvents.listen((e) {
      if (isSystemActive && (e.x.abs() > 15 || e.y.abs() > 15)) {
        _send('alert', '⚠️ تحذير: اهتزاز قوي مكتشف!');
      }
    });

    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((pos) {
      if (sLat != null && sLat != 0 && isSystemActive) {
        double dist = Geolocator.distanceBetween(sLat!, sLng!, pos.latitude, pos.longitude);
        if (dist > 50) {
          _startEmergencyProtocol(dist);
          _locSub?.cancel(); 
        }
      }
    });
  }

  void _listenToCommands() {
    _cmdSub = _dbRef.child('devices/$myCarID/commands').onValue.listen((e) async {
      if (e.snapshot.value != null && isSystemActive) {
        int id = (e.snapshot.value as Map)['id'] ?? 0;
        if (id == 1) await sendLocation();
        if (id == 2) await sendBattery();
        if (id == 3) _startDirectCalling();
      }
    });
  }

  void _startEmergencyProtocol(double dist) {
    _send('alert', '🚨 اختراق! تحركت السيارة ${dist.toInt()} متر');
    _trackSub = Stream.periodic(const Duration(seconds: 5)).listen((_) async {
      if (!isSystemActive) _trackSub?.cancel();
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _send('location', '🚀 تتبع مستمر للسيارة', lat: p.latitude, lng: p.longitude);
    });
    _startDirectCalling();
  }

  Future<void> _startDirectCalling() async {
    DataSnapshot s = await _dbRef.child('devices/$myCarID/numbers').get();
    if (!s.exists || s.value == null) return;
    
    final Map<dynamic, dynamic> d = Map<dynamic, dynamic>.from(s.value as Map);
    List<String> nums = [];
    if (d['1'] != null) nums.add(d['1'].toString());
    if (d['2'] != null) nums.add(d['2'].toString());
    if (d['3'] != null) nums.add(d['3'].toString());

    for (String n in nums) {
      if (!isSystemActive || n.isEmpty) break;
      _send('status', '📞 اتصال طوارئ بـ: $n');
      await FlutterPhoneDirectCaller.callNumber(n);
      await Future.delayed(const Duration(seconds: 45)); 
    }
  }

  void _send(String t, String m, {double? lat, double? lng}) {
    if (myCarID == null) return;
    _dbRef.child('devices/$myCarID/responses').set({
      'type': t, 'message': m, 'lat': lat, 'lng': lng, 'timestamp': ServerValue.timestamp
    });
  }

  Future<void> sendLocation() async {
    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _send('location', '📍 تم تحديث الموقع بنجاح', lat: p.latitude, lng: p.longitude);
  }

  Future<void> sendBattery() async {
    int l = await (Battery().batteryLevel);
    _send('battery', '🔋 البطارية: $l%');
  }

  Future<void> stopSecuritySystem() async {
    _vibeSub?.cancel(); _locSub?.cancel(); _cmdSub?.cancel(); _trackSub?.cancel();
    isSystemActive = false;
    await FlutterForegroundTask.stopService();
    _send('status', '🔓 الحماية متوقفة');
  }
}