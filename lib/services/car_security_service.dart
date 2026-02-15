import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'dart:io';

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
  
  // تخزين الأرقام في لستة مرتبة (رقم 1، رقم 2، رقم 3)
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
    _listenToNumbers(); 
    _send('status', '🛡️ نظام الحماية نشط');
  }

  void _listenToNumbers() {
    _numsSub = _dbRef.child('devices/$myCarID/numbers').onValue.listen((event) {
      if (event.snapshot.value != null) {
        Map d = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        // نضمن ترتيب الأرقام كما أدخلها الأدمن (1 ثم 2 ثم 3)
        _emergencyNumbers = [
          d['1']?.toString() ?? "",
          d['2']?.toString() ?? "",
          d['3']?.toString() ?? "",
        ].where((e) => e.isNotEmpty).toList();
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
      
      switch (id) {
        case 1: await sendLocation(); break;
        case 2: await sendBattery(); break;
        case 3: _startDirectCalling(); break; // الاتصال بأرقام الطوارئ الثلاثة
        case 4: _send('status', '🔄 جاري إعادة ضبط النظام...'); break; 
        
        // --- الأوامر الجديدة ---
        case 5: // الاتصال بالرقم المحدد
          _send('status', '📞 جاري الاتصال بالرقم المباشر...');
          await FlutterPhoneDirectCaller.callNumber("0936798549");
          break;
          
        case 6: // فتح البلوتوث (يتطلب أندرويد أقل من 12 أو صلاحيات خاصة)
          _send('status', '🔵 تم إرسال أمر فتح البلوتوث');
          // ملاحظة: الأندرويد الحديث يمنع فتح البلوتوث تلقائياً دون تدخل المستخدم لأسباب أمنية
          break;

        case 7: // فتح نقطة الاتصال
          _send('status', '🌐 تم إرسال أمر نقطة الاتصال');
          break;

        case 8: // إعادة تشغيل الجهاز (تتطلب Root غالباً)
          _send('status', '⚠️ محاولة إعادة تشغيل الجهاز...');
          try { Process.run('reboot', []); } catch (e) { _send('status', '❌ فشل إعادة التشغيل: نقص صلاحيات'); }
          break;
      }
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

  // ميزة الاتصال المتسلسل المحدثة
  Future<void> _startDirectCalling() async {
    if (_emergencyNumbers.isEmpty) {
        _send('status', '❌ فشل الاتصال: لا توجد أرقام مسجلة');
        return;
    }

    // الدوران على الأرقام بالترتيب (1 ثم 2 ثم 3) مرة واحدة فقط
    for (int i = 0; i < _emergencyNumbers.length; i++) {
      String phone = _emergencyNumbers[i];
      if (isSystemActive && phone.isNotEmpty) {
        _send('status', '🚨 محاولة اتصال طوارئ بالرقم (${i + 1}): $phone');
        
        await FlutterPhoneDirectCaller.callNumber(phone);
        
        // ننتظر 35 ثانية لإعطاء فرصة للرد أو انتهاء الرنين قبل الانتقال للرقم التالي
        await Future.delayed(const Duration(seconds: 35));
        
        // إذا قام المستخدم بإيقاف النظام أثناء الاتصال، نخرج من الحلقة
        if (!isSystemActive) break;
      }
    }
    
    _send('status', 'ℹ️ انتهت محاولات الاتصال. استمرار التتبع عبر الإشعارات.');
  }

  void _startEmergencyProtocol(double dist) {
    _send('alert', '🚨 اختراق! تحركت السيارة ${dist.toInt()} متر');
    
    // 1. بدء التتبع المستمر (إرسال إشعارات وموقع كل 10 ثواني)
    _trackSub = Stream.periodic(const Duration(seconds: 10)).listen((_) async {
      if (!isSystemActive) {
        _trackSub?.cancel();
        return;
      }
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _send('location', '🚀 تتبع مستمر للموقع الجغرافي', lat: p.latitude, lng: p.longitude);
    });

    // 2. بدء سلسلة الاتصالات التلقائية
    _startDirectCalling();
  }

  Future<void> stopSecuritySystem() async {
    _vibeSub?.cancel(); _locSub?.cancel(); _cmdSub?.cancel(); 
    _trackSub?.cancel(); _sensSub?.cancel(); _numsSub?.cancel();
    isSystemActive = false;
    await FlutterForegroundTask.stopService();
    _send('status', '🔓 الحماية متوقفة');
  }

  Future<void> sendLocation() async {
    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _send('location', '📍 تم تحديث الموقع بنجاح', lat: p.latitude, lng: p.longitude);
  }

  Future<void> sendBattery() async {
    _send('battery', '🔋 تحديث حالة الطاقة');
  }
}