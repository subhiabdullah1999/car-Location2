import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
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

  void initSecuritySystem() async {
    if (isSystemActive) return;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    myCarID = prefs.getString('car_id');

    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    sLat = p.latitude; sLng = p.longitude;
    isSystemActive = true;

    // 1. مراقبة الاهتزاز
    _vibeSub = accelerometerEvents.listen((e) {
      if (isSystemActive && (e.x.abs() > 15 || e.y.abs() > 15)) {
        _send('alert', '⚠️ تحذير: تم رصد اهتزاز قوي بالسيارة!');
      }
    });

    // 2. مراقبة المسافة (50 متر) + الملاحقة
    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((pos) {
      if (sLat != null && isSystemActive) {
        double dist = Geolocator.distanceBetween(sLat!, sLng!, pos.latitude, pos.longitude);
        if (dist > 50) {
          _startEmergencyProtocol(dist);
          _locSub?.cancel(); 
        }
      }
    });

    // 3. الاستماع لأوامر الأدمن
    _cmdSub = _dbRef.child('devices/$myCarID/commands').onValue.listen((e) async {
      if (e.snapshot.value != null) {
        int id = (e.snapshot.value as Map)['id'] ?? 0;
        if (id == 1) await sendLocation();
        if (id == 2) await sendBattery();
        if (id == 3) _startDirectCalling();
      }
    });
    _send('status', '🛡️ نظام الحماية نشط ويعمل الآن');
  }

  void _startEmergencyProtocol(double dist) {
    _send('alert', '🚨 اختراق! السيارة تحركت مسافة ${dist.toInt()} متر');
    
    // ملاحقة حية كل 5 ثوانٍ
    _trackSub = Stream.periodic(const Duration(seconds: 5)).listen((_) async {
      if (!isSystemActive) _trackSub?.cancel();
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _send('location', '🚀 ملاحقة مستمرة: السيارة في حالة حركة', lat: p.latitude, lng: p.longitude);
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
      _send('status', '📞 جاري الاتصال التلقائي بالطوارئ: $n');
      await FlutterPhoneDirectCaller.callNumber(n);
      await Future.delayed(const Duration(seconds: 40)); 
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
    _send('location', '📍 تم جلب الموقع الحالي بنجاح', lat: p.latitude, lng: p.longitude);
  }

  Future<void> sendBattery() async {
    int l = await Battery().batteryLevel;
    _send('battery', '🔋 مستوى شحن بطارية الجهاز: $l%');
  }

  void stopSecuritySystem() {
    _vibeSub?.cancel(); _locSub?.cancel(); _cmdSub?.cancel(); _trackSub?.cancel();
    isSystemActive = false;
    _send('status', '🔓 تم إيقاف نظام الحماية');
  }
}