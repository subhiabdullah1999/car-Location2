import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'dart:async';

class CarSecurityService {
  // نمط Singleton لضمان عمل نسخة واحدة فقط
  static final CarSecurityService _instance = CarSecurityService._internal();
  factory CarSecurityService() => _instance;
  CarSecurityService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription? _vibrationSub;
  StreamSubscription? _locationSub;
  
  bool isSystemActive = false;
  String? myCarID;
  double? startLat, startLng;
  List<String> _emergencyNumbers = [];

  // --- 1. تفعيل النظام وجلب الإعدادات ---
  Future<void> initSecuritySystem() async {
    if (isSystemActive) return;
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    myCarID = prefs.getString('car_id');
    
    if (myCarID == null) return;

    // جلب موقع البداية بدقة عالية
    Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    startLat = pos.latitude;
    startLng = pos.longitude;

    isSystemActive = true;

    // تفعيل الحساسات والمراقبة
    _listenToVibration();
    _monitorMovement();
    
    respondStatus("🛡️ نظام الحماية نشط (الموقع مثبت + مراقبة 50م)");
  }

  // --- 2. جلب أرقام الطوارئ من فايربيز ---
  Future<void> _fetchEmergencyNumbers() async {
    DataSnapshot snapshot = await _dbRef.child('devices/$myCarID/emergency_numbers').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      _emergencyNumbers = [
        data['num1']?.toString() ?? "",
        data['num2']?.toString() ?? "",
        data['num3']?.toString() ?? ""
      ].where((n) => n.isNotEmpty).toList();
    }
  }

  // --- 3. مراقبة حركة السيارة (50 متر) ---
  void _monitorMovement() {
    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, 
        distanceFilter: 10
      ),
    ).listen((Position position) async {
      if (startLat != null && startLng != null && isSystemActive) {
        double distance = Geolocator.distanceBetween(
          startLat!, startLng!, position.latitude, position.longitude
        );

        if (distance > 50) {
          _sendData('alert', '🚨 خطر: السيارة تجاوزت مسافة ${distance.toInt()} متر!');
          
          // بدء تسلسل الاتصال الذكي
          await _startSequentialCalls();
          
          // التوقف عن الاتصال المتكرر والاكتفاء بالإشعارات بعد المحاولات الثلاث
          _locationSub?.cancel();
        }
      }
    });
  }

  // --- 4. منطق الاتصال المتسلسل بالأرقام الثلاثة ---
  Future<void> _startSequentialCalls() async {
    await _fetchEmergencyNumbers(); // جلب أحدث الأرقام قبل الاتصال
    
    if (_emergencyNumbers.isEmpty) {
      respondStatus("⚠️ تنبيه: لم يتم العثور على أرقام طوارئ للاتصال بها!");
      return;
    }

    for (int i = 0; i < _emergencyNumbers.length; i++) {
      // إذا قام الأدمن بإيقاف الحماية أثناء الرنين، يتوقف التسلسل فوراً
      if (!isSystemActive) break;

      String currentNum = _emergencyNumbers[i];
      respondStatus("📞 جاري الاتصال بالرقم الاحتياطي رقم ${i + 1}...");
      
      await FlutterPhoneDirectCaller.callNumber(currentNum);

      // انتظار 40 ثانية (فترة الرنين) قبل الانتقال للرقم التالي
      await Future.delayed(const Duration(seconds: 40));
    }
    
    respondStatus("🏁 تم استنفاد محاولات الاتصال. المراقبة مستمرة عبر الإشعارات.");
  }

  // --- 5. مراقبة الاهتزاز ---
  void _listenToVibration() {
    _vibrationSub?.cancel();
    _vibrationSub = accelerometerEvents.listen((event) {
      if (isSystemActive && (event.x.abs() > 15 || event.y.abs() > 15)) {
        _sendData('alert', '⚠️ تحذير: تم رصد اهتزاز (احتمال كسر زجاج أو فتح باب)!');
      }
    });
  }

  // --- 6. دوال إرسال البيانات والتقارير ---
  void _sendData(String type, String msg, {double? lat, double? lng}) {
    if (myCarID == null) return;
    _dbRef.child('devices/$myCarID/responses').set({
      'type': type,
      'message': msg,
      'lat': lat,
      'lng': lng,
      'timestamp': ServerValue.timestamp,
    });
  }

  void respondStatus(String msg) => _sendData('status', msg);

  Future<void> sendLocationReport() async {
    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _sendData('location', '📍 موقع السيارة الحالي محدث', lat: p.latitude, lng: p.longitude);
  }

  Future<void> sendBatteryReport() async {
    int lvl = await Battery().batteryLevel;
    _sendData('battery', '🔋 مستوى بطارية الجهاز: $lvl%');
  }

  // --- 7. إيقاف النظام بالكامل ---
  void stopSecuritySystem() {
    _vibrationSub?.cancel();
    _locationSub?.cancel();
    isSystemActive = false;
    respondStatus("🔓 تم إيقاف نظام الحماية بنجاح");
  }
}