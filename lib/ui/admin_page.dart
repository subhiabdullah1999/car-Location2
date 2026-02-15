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
  
  final TextEditingController _n1 = TextEditingController();
  final TextEditingController _n2 = TextEditingController();
  final TextEditingController _n3 = TextEditingController();
  
  StreamSubscription? _statusSub;
  String _lastStatus = "انتظار التحديثات...";
  String? _carID;
  bool _isDialogShowing = false;
  bool _isExpanded = true; 

  @override
  void initState() {
    super.initState();
    _setupNotifs();
    _loadSavedNumbers(); // تحميل فوري من ذاكرة الهاتف
  }

  // دالة التحميل الفوري من ذاكرة الجهاز (تضمن ظهور الأرقام فوراً)
  void _loadSavedNumbers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _carID = prefs.getString('car_id');
    
    if (_carID != null) {
      _listenToStatus();
      
      // قراءة من الذاكرة المحلية أولاً
      setState(() {
        _n1.text = prefs.getString('num1_$_carID') ?? "";
        _n2.text = prefs.getString('num2_$_carID') ?? "";
        _n3.text = prefs.getString('num3_$_carID') ?? "";
        
        // إذا وجدت أرقام، اغلق القائمة فوراً
        if (_n1.text.isNotEmpty) {
          _isExpanded = false;
        }
      });

      // ثم التحديث من Firebase في الخلفية للتأكد من المزامنة
      _dbRef.child('devices/$_carID/numbers').get().then((snapshot) {
        if (snapshot.exists && snapshot.value != null) {
          Map d = Map<dynamic, dynamic>.from(snapshot.value as Map);
          setState(() {
            _n1.text = d['1']?.toString() ?? _n1.text;
            _n2.text = d['2']?.toString() ?? _n2.text;
            _n3.text = d['3']?.toString() ?? _n3.text;
          });
        }
      });
    }
  }

  void _setupNotifs() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(const InitializationSettings(android: androidInit));
  }

  void _listenToStatus() {
    _statusSub = _dbRef.child('devices/$_carID/responses').onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      Map d = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      setState(() { _lastStatus = d['message'] ?? ""; });
      _handleResponse(d);
    });
  }

  void _handleResponse(Map d) async {
    String type = d['type'] ?? '';
    String msg = d['message'] ?? '';
    await _audioPlayer.stop();
    await _audioPlayer.play(AssetSource(type == 'alert' ? 'sounds/alarm.mp3' : 'sounds/notification.mp3'));
    await _notif.show(1, type == 'alert' ? "🚨 تنبيه أمني" : "ℹ️ تحديث HASBA", msg, const NotificationDetails(android: AndroidNotificationDetails('high_channel', 'تنبيهات', importance: Importance.max, priority: Priority.high)));
    if (mounted && !_isDialogShowing) _showSimpleDialog(type, msg, d);
  }

  void _showSimpleDialog(String type, String msg, Map d) {
    _isDialogShowing = true;
    showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
      title: Text(type == 'alert' ? "🚨 تحذير" : "ℹ️ إشعار"),
      content: Text(msg),
      actions: [
        if (d['lat'] != null) ElevatedButton(onPressed: () => launchUrl(Uri.parse("https://www.google.com/maps/search/?api=1&query=${d['lat']},${d['lng']}")), child: const Text("فتح الخريطة")),
        TextButton(onPressed: () { _isDialogShowing = false; Navigator.pop(c); }, child: const Text("موافق")),
      ],
    )).then((_) => _isDialogShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("تحكم السيارة (${_carID ?? ''})"),
        backgroundColor: Colors.blue.shade900,
        leading: IconButton(icon: const Icon(Icons.exit_to_app), onPressed: () async {
          // عند تسجيل الخروج، لا نمسح الأرقام المحفوظة، فقط نمسح الـ car_id إذا أردت
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AppTypeSelector()));
        }),
      ),
      body: _carID == null 
          ? const Center(child: CircularProgressIndicator()) 
          : SingleChildScrollView(
              child: Column(
                children: [
                  _statusWidget(),
                  _sensitivityStreamWidget(),
                  _numbersWidget(),
                  _actionsWidget(),
                ],
              ),
            ),
    );
  }

  Widget _numbersWidget() {
    return Card(
      margin: const EdgeInsets.all(15),
      child: ExpansionTile(
        key: GlobalKey(), // يضمن تحديث الحالة (مفتوح/مغلق) برمجياً
        initiallyExpanded: _isExpanded,
        onExpansionChanged: (val) => setState(() => _isExpanded = val),
        title: const Text("📞 أرقام الطوارئ المحفوظة"),
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(children: [
              TextField(controller: _n1, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "رقم 1", prefixIcon: Icon(Icons.phone))),
              TextField(controller: _n2, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "رقم 2", prefixIcon: Icon(Icons.phone))),
              TextField(controller: _n3, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "رقم 3", prefixIcon: Icon(Icons.phone))),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, minimumSize: const Size(double.infinity, 50)),
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: () async {
                  // 1. الحفظ في Firebase
                  await _dbRef.child('devices/$_carID/numbers').set({'1': _n1.text, '2': _n2.text, '3': _n3.text});
                  
                  // 2. الحفظ في ذاكرة الهاتف (السر في بقاء الأرقام)
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setString('num1_$_carID', _n1.text);
                  await prefs.setString('num2_$_carID', _n2.text);
                  await prefs.setString('num3_$_carID', _n3.text);

                  setState(() { _isExpanded = false; }); // إغلاق القائمة
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ تم الحفظ في الهاتف والسحابة بنجاح")));
                }, 
                label: const Text("حفظ وتعديل", style: TextStyle(color: Colors.white)),
              ),
            ]),
          )
        ],
      ),
    );
  }

  // (بقية الودجات كما هي دون تغيير لضمان الحفاظ على الشكل والمميزات)
  Widget _statusWidget() => Container(
    padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10)]),
    child: Row(children: [const Icon(Icons.info_outline, color: Colors.blue), const SizedBox(width: 15), Expanded(child: Text(_lastStatus, style: const TextStyle(fontWeight: FontWeight.bold)))]),
  );

  Widget _sensitivityStreamWidget() => StreamBuilder(
    stream: _dbRef.child('devices/$_carID/sensitivity').onValue,
    builder: (context, snapshot) {
      int currentVal = 20;
      if (snapshot.hasData && snapshot.data!.snapshot.value != null) currentVal = int.parse(snapshot.data!.snapshot.value.toString());
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 15),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(children: [
            const Text("🎚️ حساسية الاهتزاز", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 35), onPressed: () => _dbRef.child('devices/$_carID/sensitivity').set(currentVal > 5 ? currentVal - 5 : 5)),
              Text("$currentVal", style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 35), onPressed: () => _dbRef.child('devices/$_carID/sensitivity').set(currentVal < 100 ? currentVal + 5 : 100)),
            ])
          ]),
        ),
      );
    }
  );

  Widget _actionsWidget() => GridView.count(
    shrinkWrap: true, 
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2, 
    padding: const EdgeInsets.all(15), 
    mainAxisSpacing: 10, 
    crossAxisSpacing: 10,
    childAspectRatio: 1.2, // لتناسب الأيقونات الجديدة
    children: [
      _actionBtn(1, "تتبع الموقع", Icons.map, Colors.blue),
      _actionBtn(2, "حالة البطارية", Icons.battery_charging_full, Colors.green),
      // _actionBtn(3, "طوارئ (3 أرقام)", Icons.contact_phone, Colors.red),
      _actionBtn(4, "إعادة ضبط", Icons.refresh, Colors.orange),
      
      // الأزرار الجديدة
      _actionBtn(5, "اتصال بالسيارة", Icons.phone_forwarded, Colors.teal),
      _actionBtn(6, "فتح البلوتوث", Icons.bluetooth, Colors.indigo),
      _actionBtn(7, "نقطة اتصال", Icons.wifi_tethering, Colors.deepPurple),
      _actionBtn(8, "إعادة تشغيل", Icons.power_settings_new, Colors.redAccent),
    ],
  );

  Widget _actionBtn(int id, String l, IconData i, Color c) => Card(
    child: InkWell(
      onTap: () => _dbRef.child('devices/$_carID/commands').set({'id': id, 'timestamp': ServerValue.timestamp}),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 40), const SizedBox(height: 5), Text(l, textAlign: TextAlign.center)]),
    ),
  );

  @override
  void dispose() { 
    _statusSub?.cancel(); 
    _n1.dispose(); _n2.dispose(); _n3.dispose();
    _audioPlayer.dispose(); 
    super.dispose(); 
  }
}