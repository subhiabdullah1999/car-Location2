import 'package:car_location/main.dart';
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
  String _lastStatus = "انتظار التحديثات...";
  String? _carID;

  @override
  void initState() {
    super.initState();
    _setupNotifs();
    _loadData();
  }

  void _setupNotifs() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(const InitializationSettings(android: androidInit));
    const channel = AndroidNotificationChannel('high_channel', 'Alerts', importance: Importance.max, playSound: true);
    await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  void _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _carID = prefs.getString('car_id');
    if (_carID != null) {
      _listen();
      // جلب الأرقام المسجلة مسبقاً من Firebase
      _dbRef.child('devices/$_carID/numbers').once().then((DatabaseEvent event) {
        if (event.snapshot.value != null) {
          Map d = event.snapshot.value as Map;
          setState(() {
            _n1.text = d['1'] ?? "";
            _n2.text = d['2'] ?? "";
            _n3.text = d['3'] ?? "";
          });
        }
      });
    }
  }

  void _listen() {
    _sub = _dbRef.child('devices/$_carID/responses').onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      Map d = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      setState(() { _lastStatus = d['message'] ?? ""; });
      _handleResponse(d);
    });
  }

  void _handleResponse(Map d) async {
    String type = d['type'] ?? '';
    // صوت التنبيه
    await _audioPlayer.stop();
    await _audioPlayer.play(AssetSource(type == 'alert' ? 'sounds/alarm.mp3' : 'sounds/notification.mp3'));

    // الإشعار المنبثق العلوي
    const android = AndroidNotificationDetails('high_channel', 'Alerts', importance: Importance.max, priority: Priority.high);
    await _notif.show(0, "تنبيه HASBA", d['message'], const NotificationDetails(android: android));

    // النافذة التفاعلية داخل التطبيق
    if (mounted) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(type == 'alert' ? "🚨 تحذير أمني" : "ℹ️ إشعار"),
          content: Text(d['message']),
          actions: [
            if (type == 'location') ElevatedButton.icon(
              icon: const Icon(Icons.location_on),
              label: const Text("فتح في خرائط جوجل"),
              onPressed: () => launchUrl(Uri.parse("https://www.google.com/maps/search/?api=1&query=${d['lat']},${d['lng']}"), mode: LaunchMode.externalApplication),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("إغلاق")),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تحكم السيارة ($_carID)"),
        backgroundColor: Colors.blue.shade900,
        leading: IconButton(icon: const Icon(Icons.logout), onPressed: () async {
           SharedPreferences prefs = await SharedPreferences.getInstance();
           await prefs.clear(); // مسح البيانات للعودة للبداية
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AppTypeSelector()));
        }),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _statusWidget(),
            _numbersWidget(),
            _actionsWidget(),
          ],
        ),
      ),
    );
  }

  Widget _statusWidget() => Container(
    padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
    child: Row(children: [const Icon(Icons.radar, color: Colors.blue), const SizedBox(width: 15), Expanded(child: Text(_lastStatus, style: const TextStyle(fontWeight: FontWeight.bold)))]),
  );

  Widget _numbersWidget() => Card(
    margin: const EdgeInsets.symmetric(horizontal: 15),
    child: ExpansionTile(
      title: const Text("أرقام الطوارئ الثلاثة"),
      children: [
        Padding(padding: const EdgeInsets.all(15), child: Column(children: [
          TextField(controller: _n1, decoration: const InputDecoration(labelText: "رقم 1 (أساسي)")),
          TextField(controller: _n2, decoration: const InputDecoration(labelText: "رقم 2")),
          TextField(controller: _n3, decoration: const InputDecoration(labelText: "رقم 3")),
          ElevatedButton(onPressed: () {
            _dbRef.child('devices/$_carID/numbers').set({'1': _n1.text, '2': _n2.text, '3': _n3.text});
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحفظ")));
          }, child: const Text("حفظ الأرقام")),
        ]))
      ],
    ),
  );

  Widget _actionsWidget() => GridView.count(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, padding: const EdgeInsets.all(15), mainAxisSpacing: 10, crossAxisSpacing: 10,
    children: [
      _actionBtn(1, "تتبع الموقع", Icons.map, Colors.blue),
      _actionBtn(2, "حالة البطارية", Icons.battery_charging_full, Colors.green),
      _actionBtn(3, "الميكروفون", Icons.mic, Colors.red),
      _actionBtn(4, "إعادة ضبط", Icons.refresh, Colors.orange),
    ],
  );

  Widget _actionBtn(int id, String l, IconData i, Color c) => Card(
    child: InkWell(
      onTap: () => _dbRef.child('devices/$_carID/commands').set({'id': id, 't': ServerValue.timestamp}),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 40), Text(l)]),
    ),
  );

  @override
  void dispose() { _sub?.cancel(); _audioPlayer.dispose(); super.dispose(); }
}