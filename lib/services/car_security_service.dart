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
  StreamSubscription? _vibeSub, _locSub, _cmdSub, _trackSub, _sensSub, _numsSub;
  bool isSystemActive = false;
  String? myCarID;
  double? sLat, sLng;
  double _threshold = 20.0;
  
  // قائمة الأرقام التي سيتم تحديثها لحظياً
  List<String> _emergencyNumbers = [];

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

  Future<void> initSecuritySystem() async {
    if (isSystemActive) return;
    initForegroundTask();
    await FlutterForegroundTask.startService(
      notificationTitle: '🛡️ نظام حماية HASBA نشط',
      notificationText: 'جاري مراقبة السيارة وحمايتها الآن...',
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    myCarID = prefs.getString('car_id');

    Position? p = await Geolocator.getLastKnownPosition() ?? 
                 await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);

    sLat = p.latitude; sLng = p.longitude;
    isSystemActive = true;

    _startSensors();
    _listenToCommands();
    _listenToNumbers(); // البدء بمراقبة الأرقام فور تفعيل النظام
    _send('status', '🛡️ نظام الحماية نشط');
  }

  // ميزة المراقبة اللحظية للأرقام من طرف جهاز السيارة
  void _listenToNumbers() {
    _numsSub = _dbRef.child('devices/$myCarID/numbers').onValue.listen((event) {
      if (event.snapshot.value != null) {
        Map d = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        _emergencyNumbers = d.values.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    });
  }

  void _listenToSensitivity() {
    _sensSub = _dbRef.child('devices/$myCarID/sensitivity').onValue.listen((event) {
      if (event.snapshot.value != null) {
        _threshold = double.parse(event.snapshot.value.toString());
      }
    });
  }

  void _startSensors() {
    _listenToSensitivity();
    _vibeSub = accelerometerEvents.listen((e) {
      if (isSystemActive && (e.x.abs() > _threshold || e.y.abs() > _threshold || e.z.abs() > _threshold)) {
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

  void _send(String t, String m, {double? lat, double? lng}) async {
    if (myCarID == null) return;
    int batteryLevel = await Battery().batteryLevel;
    DateTime now = DateTime.now();
    String formattedTime = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    String formattedDate = "${now.year}/${now.month}/${now.day}";
    String finalMessage = "$m\n🔋 $batteryLevel% | 🕒 $formattedTime | 📅 $formattedDate";

    _dbRef.child('devices/$myCarID/responses').set({
      'type': t, 
      'message': finalMessage, 
      'lat': lat, 
      'lng': lng, 
      'timestamp': ServerValue.timestamp
    });
  }

  Future<void> _startDirectCalling() async {
    // يستخدم الآن القائمة المحدثة لحظياً _emergencyNumbers
    if (_emergencyNumbers.isEmpty) {
        _send('status', '❌ فشل الاتصال: لا توجد أرقام طوارئ مسجلة');
        return;
    }

    for (var n in _emergencyNumbers) {
      if (isSystemActive && n.isNotEmpty) {
        _send('status', '📞 جاري الاتصال بالطوارئ: $n');
        await FlutterPhoneDirectCaller.callNumber(n);
        await Future.delayed(const Duration(seconds: 45));
      }
    }
  }

  Future<void> stopSecuritySystem() async {
    _vibeSub?.cancel(); _locSub?.cancel(); _cmdSub?.cancel(); 
    _trackSub?.cancel(); _sensSub?.cancel(); _numsSub?.cancel();
    isSystemActive = false;
    await FlutterForegroundTask.stopService();
    _send('status', '🔓 الحماية متوقفة');
  }

  void _startEmergencyProtocol(double dist) {
    _send('alert', '🚨 اختراق! تحركت السيارة ${dist.toInt()} متر');
    _trackSub = Stream.periodic(const Duration(seconds: 10)).listen((_) async {
      if (!isSystemActive) _trackSub?.cancel();
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _send('location', '🚀 تتبع مستمر', lat: p.latitude, lng: p.longitude);
    });
    _startDirectCalling();
  }

  Future<void> sendLocation() async {
    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _send('location', '📍 تم تحديث الموقع بنجاح', lat: p.latitude, lng: p.longitude);
  }

  Future<void> sendBattery() async {
    _send('battery', '🔋 تحديث حالة الطاقة');
  }
}