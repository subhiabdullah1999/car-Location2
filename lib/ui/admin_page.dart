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
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  
  final TextEditingController _n1 = TextEditingController(), _n2 = TextEditingController(), _n3 = TextEditingController();
  StreamSubscription? _sub;
  String _lastStatus = "جاري الاتصال بالسيارة...";
  String? _carID;

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _initAdmin();
  }

  void _setupNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(const InitializationSettings(android: androidInit));
    
    // إنشاء قناة إشعارات ذات أولوية قصوى لتظهر كمنبثقة (Heads-up)
    const channel = AndroidNotificationChannel(
      'car_alerts', 'تنبيهات السيارة',
      description: 'هذه القناة مخصصة لحماية السيارة',
      importance: Importance.max,
      playSound: true,
    );
    await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  void _initAdmin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _carID = prefs.getString('car_id');
    if (_carID != null) {
      _listenToCar();
      DataSnapshot s = await _dbRef.child('devices/$_carID/numbers').get();
      if (s.exists) {
        Map d = s.value as Map;
        setState(() { _n1.text = d['1']??""; _n2.text = d['2']??""; _n3.text = d['3']??""; });
      }
    }
  }

  void _listenToCar() {
    _sub = _dbRef.child('devices/$_carID/responses').onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      Map data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      
      String type = data['type'] ?? '';
      String msg = data['message'] ?? '';

      setState(() { _lastStatus = msg; });
      
      _triggerAlert(type, msg, data);
    });
  }

  void _triggerAlert(String type, String msg, Map data) async {
    // 1. تشغيل الصوت المخصص
    await _audioPlayer.stop();
    await _audioPlayer.play(AssetSource(type == 'alert' ? 'sounds/alarm.mp3' : 'sounds/notification.mp3'));

    // 2. إرسال إشعار منبثق للنظام (يعمل والتطبيق مغلق)
    const androidDetails = AndroidNotificationDetails(
      'car_alerts', 'تنبيهات السيارة',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true, // لجعلها تظهر فوق التطبيقات الأخرى
    );
    _notif.show(DateTime.now().millisecond, "HASBA TRKAR: " + (type == 'alert' ? "🚨 تحذير" : "ℹ️ تحديث"), msg, const NotificationDetails(android: androidDetails));

    // 3. إظهار نافذة داخل التطبيق مع زر الخريطة
    if (mounted) {
      showDialog(context: context, builder: (c) => AlertDialog(
        title: Text(type == 'alert' ? "🚨 إنذار خطر" : "ℹ️ إشعار"),
        content: Text(msg),
        actions: [
          if (type == 'location') ElevatedButton.icon(
            icon: const Icon(Icons.map), label: const Text("فتح الخريطة"),
            onPressed: () => launchUrl(Uri.parse("https://www.google.com/maps/search/?api=1&query=${data['lat']},${data['lng']}"), mode: LaunchMode.externalApplication),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("موافق")),
        ],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("لوحة التحكم ($_carID)"), backgroundColor: Colors.blue.shade900, elevation: 10),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _statusCard(),
            _numbersSection(),
            const Padding(padding: EdgeInsets.all(10), child: Text("الأوامر السريعة", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            _actionsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.shade100), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)]),
      child: Column(children: [
        const Icon(Icons.radar, color: Colors.blue, size: 30),
        const SizedBox(height: 10),
        Text(_lastStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
      ]),
    );
  }

  Widget _numbersSection() {
    return Card(margin: const EdgeInsets.symmetric(horizontal: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        leading: const Icon(Icons.phone_paused, color: Colors.red),
        title: const Text("إعدادات أرقام الطوارئ"),
        children: [
          Padding(padding: const EdgeInsets.all(15), child: Column(children: [
            TextField(controller: _n1, decoration: const InputDecoration(labelText: "رقم الطوارئ 1", icon: Icon(Icons.looks_one))),
            TextField(controller: _n2, decoration: const InputDecoration(labelText: "رقم الطوارئ 2", icon: Icon(Icons.looks_two))),
            TextField(controller: _n3, decoration: const InputDecoration(labelText: "رقم الطوارئ 3", icon: Icon(Icons.looks_3))),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: () => _dbRef.child('devices/$_carID/numbers').set({'1': _n1.text, '2': _n2.text, '3': _n3.text}), child: const Text("حفظ الأرقام")),
          ]))
        ],
      ),
    );
  }

  Widget _actionsGrid() {
    return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, padding: const EdgeInsets.all(15), mainAxisSpacing: 10, crossAxisSpacing: 10,
      children: [
        _cmdBtn(1, "جلب الموقع", Icons.location_searching, Colors.blue),
        _cmdBtn(2, "حالة البطارية", Icons.battery_charging_full, Colors.green),
        _cmdBtn(3, "تنبيه/ميكروفون", Icons.record_voice_over, Colors.red),
        _cmdBtn(4, "إعادة ضبط", Icons.refresh, Colors.orange),
      ],
    );
  }

  Widget _cmdBtn(int id, String l, IconData i, Color c) {
    return InkWell(
      onTap: () => _dbRef.child('devices/$_carID/commands').set({'id': id, 't': ServerValue.timestamp}),
      child: Card(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 40, color: c), const SizedBox(height: 10), Text(l, style: const TextStyle(fontWeight: FontWeight.bold))])),
    );
  }

  @override
  void dispose() { _sub?.cancel(); _audioPlayer.dispose(); super.dispose(); }
}