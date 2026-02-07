import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notifPlugin = FlutterLocalNotificationsPlugin();
  
  // متحكمات أرقام الطوارئ
  final TextEditingController _num1Controller = TextEditingController();
  final TextEditingController _num2Controller = TextEditingController();
  final TextEditingController _num3Controller = TextEditingController();

  StreamSubscription? _carSubscription;
  String _lastStatus = "جاري جلب البيانات...";
  String? _carID;

  @override
  void initState() {
    super.initState();
    _loadConfigAndData();
  }

  // تحميل المعرف وجلب الأرقام المخزنة مسبقاً من فايربيز
  void _loadConfigAndData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _carID = prefs.getString('car_id');
    
    if (_carID != null) {
      _listenToCarResponses();
      _fetchSavedNumbers();
    }
  }

  void _fetchSavedNumbers() async {
    DataSnapshot snapshot = await _dbRef.child('devices/$_carID/emergency_numbers').get();
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      setState(() {
        _num1Controller.text = data['num1'] ?? "";
        _num2Controller.text = data['num2'] ?? "";
        _num3Controller.text = data['num3'] ?? "";
      });
    }
  }

  void _saveEmergencyNumbers() {
    if (_carID == null) return;
    _dbRef.child('devices/$_carID/emergency_numbers').set({
      'num1': _num1Controller.text,
      'num2': _num2Controller.text,
      'num3': _num3Controller.text,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ تم حفظ أرقام الطوارئ وإرسالها للسيارة")),
    );
  }

  void _listenToCarResponses() {
    _carSubscription = _dbRef.child('devices/$_carID/responses').onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      Map data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      String type = data['type'] ?? '';
      String message = data['message'] ?? '';

      setState(() { _lastStatus = message; });
      
      // تشغيل الصوت المخصص
      _audioPlayer.play(AssetSource(type == 'alert' ? 'sounds/alarm.mp3' : 'sounds/not.mp3'));
      
      if (type == 'alert' || type == 'location') {
        _showNotificationDialog(type, data);
      }
    });
  }

  void _sendCommand(int cmd) {
    _dbRef.child('devices/$_carID/commands').set({
      'id': cmd, 
      'timestamp': ServerValue.timestamp
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تحكم السيارة ($_carID)"),
        backgroundColor: Colors.blue.shade900,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // حالة السيارة الحالية
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.satellite_alt, color: Colors.blue),
                  const SizedBox(width: 15),
                  Expanded(child: Text(_lastStatus, style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            // قسم إعدادات أرقام الطوارئ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ExpansionTile(
                  leading: const Icon(Icons.phone_forwarded, color: Colors.red),
                  title: const Text("أرقام اتصال الطوارئ (تسلسلي)", style: TextStyle(fontWeight: FontWeight.bold)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          _buildPhoneField(_num1Controller, "الرقم الأول (أساسي)", Icons.looks_one),
                          _buildPhoneField(_num2Controller, "الرقم الثاني (احتياطي)", Icons.looks_two),
                          _buildPhoneField(_num3Controller, "الرقم الثالث (احتياطي)", Icons.looks_3),
                          const SizedBox(height: 15),
                          ElevatedButton.icon(
                            onPressed: _saveEmergencyNumbers,
                            icon: const Icon(Icons.save),
                            label: const Text("حفظ الأرقام"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // أزرار التحكم (التصميم الأصلي)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              padding: const EdgeInsets.all(15),
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              children: [
                _buildCmdButton(1, "طلب الموقع", Icons.location_on, Colors.blue),
                _buildCmdButton(2, "حالة البطارية", Icons.battery_charging_full, Colors.green),
                _buildCmdButton(3, "فحص الجهاز", Icons.edgesensor_high, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneField(TextEditingController controller, String hint, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20),
          labelText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        ),
      ),
    );
  }

  Widget _buildCmdButton(int id, String label, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () => _sendCommand(id),
        borderRadius: BorderRadius.circular(15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showNotificationDialog(String type, Map data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(type == 'alert' ? "🚨 تنبيه أمني" : "📍 موقع السيارة"),
        content: Text(data['message']),
        actions: [
          if (type == 'location') 
            TextButton(onPressed: () => _openMap(data['lat'], data['lng']), child: const Text("فتح الخريطة")),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إغلاق")),
        ],
      ),
    );
  }

  Future<void> _openMap(dynamic lat, dynamic lng) async {
    final url = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _carSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}