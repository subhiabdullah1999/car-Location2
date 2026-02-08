import 'package:car_location/ui/admin_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'services/car_security_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.databaseURL = "https://car-location-67e15-default-rtdb.firebaseio.com/";
  await requestPermissions(); 
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: SplashScreen()));
}

Future<void> requestPermissions() async {
  await [Permission.location, Permission.phone, Permission.sensors, Permission.ignoreBatteryOptimizations, Permission.notification].request();
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0.0; double _scale = 0.5;
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () => setState(() { _opacity = 1.0; _scale = 1.0; }));
    Timer(const Duration(milliseconds: 3500), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AppTypeSelector())));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: Center(
        child: AnimatedScale(
          scale: _scale, duration: const Duration(milliseconds: 1500), curve: Curves.elasticOut,
          child: AnimatedOpacity(opacity: _opacity, duration: const Duration(milliseconds: 1000), child: Image.asset('assets/images/logohasba.png', width: 250)),
        ),
      ),
    );
  }
}

class AppTypeSelector extends StatefulWidget {
  const AppTypeSelector({super.key});
  @override
  State<AppTypeSelector> createState() => _AppTypeSelectorState();
}

class _AppTypeSelectorState extends State<AppTypeSelector> {
  final TextEditingController _idController = TextEditingController();

  void _saveIDAndGo(Widget target) async {
    if (_idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال معرف السيارة")));
      return;
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('car_id', _idController.text);
    Navigator.push(context, MaterialPageRoute(builder: (context) => target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car_filled, size: 80, color: Colors.blue),
            const Text("HASBA TRKAR", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(controller: _idController, decoration: InputDecoration(labelText: "معرف السيارة (رقم الهاتف)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
            const SizedBox(height: 20),
            _buildSelectorBtn("لوحة التحكم (الأدمن)", Icons.admin_panel_settings, Colors.blue.shade800, () => _saveIDAndGo(const AdminPage())),
            const SizedBox(height: 15),
            _buildSelectorBtn("جهاز السيارة (المراقب)", Icons.vibration, Colors.grey.shade900, () => _saveIDAndGo(const CarAppDevice())),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorBtn(String t, IconData i, Color c, VoidCallback p) {
    return ElevatedButton.icon(
      icon: Icon(i, color: Colors.white), label: Text(t, style: const TextStyle(color: Colors.white, fontSize: 16)),
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 65), backgroundColor: c, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      onPressed: p,
    );
  }
}

class CarAppDevice extends StatefulWidget {
  const CarAppDevice({super.key});
  @override
  State<CarAppDevice> createState() => _CarAppDeviceState();
}

class _CarAppDeviceState extends State<CarAppDevice> {
  final CarSecurityService _service = CarSecurityService();
  @override
  Widget build(BuildContext context) {
    bool active = _service.isSystemActive;
    return Scaffold(
      appBar: AppBar(title: const Text("وضع مراقبة السيارة")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? Icons.shield : Icons.shield_outlined, size: 120, color: active ? Colors.green : Colors.red),
            const SizedBox(height: 20),
            Text(active ? "النظام يعمل في الخلفية" : "النظام متوقف", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: Icon(active ? Icons.stop_circle : Icons.play_circle_fill, color: Colors.white),
              label: Text(active ? "إيقاف الحماية" : "تفعيل الحماية", style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: active ? Colors.red : Colors.green, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
              onPressed: () => setState(() { active ? _service.stopSecuritySystem() : _service.initSecuritySystem(); }),
            ),
          ],
        ),
      ),
    );
  }
}