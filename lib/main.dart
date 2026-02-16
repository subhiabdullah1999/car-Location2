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

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedID = prefs.getString('car_id');
  String? userType = prefs.getString('user_type');

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(savedID: savedID, userType: userType),
  ));
}

Future<void> requestPermissions() async {
  // طلب صلاحية الظهور فوق التطبيقات ضروري جداً لبدء المكالمة من الخلفية
  if (await Permission.systemAlertWindow.isDenied) {
    await Permission.systemAlertWindow.request();
  }
  await [Permission.location, Permission.phone, Permission.sensors,
   Permission.ignoreBatteryOptimizations,
   Permission.systemAlertWindow,
    Permission.notification].request();
}

class SplashScreen extends StatefulWidget {
  final String? savedID;
  final String? userType;
  const SplashScreen({super.key, this.savedID, this.userType});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (widget.savedID != null && widget.userType != null) {
        if (widget.userType == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminPage()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const CarAppDevice()));
        }
      } else {
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

class AppTypeSelector extends StatefulWidget {
  const AppTypeSelector({super.key});
  @override
  State<AppTypeSelector> createState() => _AppTypeSelectorState();
}

class _AppTypeSelectorState extends State<AppTypeSelector> {
  final TextEditingController _idController = TextEditingController();

 void _saveIDAndGo(String type, Widget target) async {
    if (_idController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال رقم هاتف السيارة")));
      return;
    }

    String carId = _idController.text;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('car_id', carId);
    await prefs.setString('user_type', type);

    // نرفع القيمة في الخلفية دون انتظار "await" لكي لا يتوقف التطبيق
    FirebaseDatabase.instance.ref().child('devices/$carId/sensitivity').get().then((snapshot) {
      if (!snapshot.exists) {
        FirebaseDatabase.instance.ref().child('devices/$carId/sensitivity').set(20);
      }
    });

    // الانتقال الفوري للشاشة التالية
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 100),
              const Icon(Icons.security, size: 80, color: Colors.blue),
              const Text("HASBA TRKAR", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TextField(
                controller: _idController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: "أدخل رقم هاتف السيارة (المعرف)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
              const SizedBox(height: 20),
              _btn("أنا الأدمن (تتبع وتحكم)", Icons.admin_panel_settings, Colors.blue.shade700, () => _saveIDAndGo('admin', const AdminPage())),
              const SizedBox(height: 10),
              _btn("جهاز السيارة (مراقب وحساس)", Icons.vibration, Colors.grey.shade800, () => _saveIDAndGo('device', const CarAppDevice())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String t, IconData i, Color c, VoidCallback onPress) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: c),
      onPressed: onPress,
      icon: Icon(i, color: Colors.white),
      label: Text(t, style: const TextStyle(color: Colors.white)),
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
  bool _isLoading = false;

  Future<void> _handleSystemToggle() async {
    setState(() => _isLoading = true);
    try {
      if (_service.isSystemActive) {
        await _service.stopSecuritySystem();
      } else {
        await _service.initSecuritySystem();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool active = _service.isSystemActive;
    return Scaffold(
      appBar: AppBar(
        title: const Text("جهاز تتبع السيارة"),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.remove('user_type');
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AppTypeSelector()));
          },
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? Icons.security : Icons.security_outlined, size: 120, color: active ? Colors.green : Colors.red),
            const SizedBox(height: 20),
            Text(active ? "نظام الحماية: نشط" : "نظام الحماية: متوقف", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            SizedBox(
              width: 260, height: 65,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading ? Colors.grey : (active ? Colors.red : Colors.green),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                ),
                onPressed: _isLoading ? null : _handleSystemToggle,
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(active ? "إيقاف نظام الحماية" : "تفعيل نظام الحماية", style: const TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}