import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart' as AutoStartFlutter;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// استيراد الملفات (تأكد من مطابقة المسارات لمجلدات مشروعك)
import 'ui/admin_page.dart';
import 'services/car_security_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.databaseURL = "https://car-location-67e15-default-rtdb.firebaseio.com/";

  await requestPermissions(); 

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(),
  ));
}

Future<void> requestPermissions() async {
  await [
    Permission.location,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
    Permission.sensors,
    Permission.phone,
  ].request();

  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isAutoStartRequested = prefs.getBool('auto_start_requested') ?? false;

  if (!isAutoStartRequested) {
    try {
      bool? isAutoStartAvailable = await AutoStartFlutter.isAutoStartAvailable;
      if (isAutoStartAvailable == true) {
        await prefs.setBool('auto_start_requested', true);
        await AutoStartFlutter.getAutoStartPermission();
      }
    } catch (e) {
      debugPrint("خطأ في التشغيل التلقائي: $e");
    }
  }
}

// --- شاشة السبلاش (SplashScreen) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AppTypeSelector()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Center(child: Image.asset('assets/images/logohasba.png', width: 250)),
    );
  }
}

// --- شاشة اختيار نوع التطبيق (AppTypeSelector) ---
class AppTypeSelector extends StatefulWidget {
  const AppTypeSelector({super.key});
  @override
  State<AppTypeSelector> createState() => _AppTypeSelectorState();
}

class _AppTypeSelectorState extends State<AppTypeSelector> {
  final TextEditingController _idController = TextEditingController();

  void _saveAndNavigate(Widget target) async {
    if (_idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال رقم هاتف السيارة أولاً")));
      return;
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('car_id', _idController.text);
    Navigator.push(context, MaterialPageRoute(builder: (context) => target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          height: MediaQuery.of(context).size.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security_update_good, size: 80, color: Color(0xFF0D47A1)),
              const Text("HASBA TRKAR", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TextField(
                controller: _idController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "رقم هاتف السيارة (المعرف)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  prefixIcon: const Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 30),
              _selectionButton("أنا الأدمن (تتبع وتحكم)", Icons.admin_panel_settings, const Color(0xFF0D47A1), const AdminPage()),
              const SizedBox(height: 15),
              _selectionButton("جهاز السيارة (مراقب)", Icons.directions_car, Colors.blueGrey[800]!, const CarAppDevice()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionButton(String title, IconData icon, Color color, Widget target) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(title),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 60),
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: () => _saveAndNavigate(target),
    );
  }
}

// --- شاشة جهاز السيارة (CarAppDevice) ---
class CarAppDevice extends StatefulWidget {
  const CarAppDevice({super.key});
  @override
  State<CarAppDevice> createState() => _CarAppDeviceState();
}

class _CarAppDeviceState extends State<CarAppDevice> {
  final CarSecurityService _service = CarSecurityService();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription? _commandSub;
  String? _carID;

  @override
  void initState() {
    super.initState();
    _loadIDAndListen();
  }

  void _loadIDAndListen() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _carID = prefs.getString('car_id');
    if (_carID != null) {
      _commandSub = _dbRef.child('devices/$_carID/commands').onValue.listen((event) async {
        if (event.snapshot.value != null) {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final int cmdId = data['id'] ?? 0;
          if (cmdId == 1) await _service.sendLocationReport();
          if (cmdId == 2) await _service.sendBatteryReport();
          if (cmdId == 3) _service.respondStatus("الجهاز متصل ومستعد");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("وحدة السيارة ($_carID)"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user, size: 120, color: _service.isSystemActive ? Colors.green : Colors.grey),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _service.isSystemActive ? Colors.red : Colors.green, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20)),
              onPressed: () {
                setState(() {
                  _service.isSystemActive ? _service.stopSecuritySystem() : _service.initSecuritySystem();
                });
              },
              child: Text(_service.isSystemActive ? "إيقاف الحماية" : "تفعيل الحماية الآن", style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commandSub?.cancel();
    super.dispose();
  }
}