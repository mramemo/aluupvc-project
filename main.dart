import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

enum WinType { sliding2, sliding4, hinged1, hinged2 }

extension WinTypeX on WinType {
  String get label {
    switch (this) {
      case WinType.sliding2:
        return "جرّار 2 ضلفة";
      case WinType.sliding4:
        return "جرّار 4 ضلفة";
      case WinType.hinged1:
        return "مفصلي ضلفة";
      case WinType.hinged2:
        return "مفصلي 2 ضلفة";
    }
  }

  int get sashes {
    switch (this) {
      case WinType.sliding2:
        return 2;
      case WinType.sliding4:
        return 4;
      case WinType.hinged1:
        return 1;
      case WinType.hinged2:
        return 2;
    }
  }

  bool get isSliding => this == WinType.sliding2 || this == WinType.sliding4;
}

class ProjectItem {
  double wCm;
  double hCm;
  int qty;
  WinType type;
  bool hasWire; // للسلك في الجرار فقط

  ProjectItem({
    required this.wCm,
    required this.hCm,
    required this.qty,
    required this.type,
    required this.hasWire,
  });
}

class SettingsModel {
  double frameW; // خصم عرض الفرام (سم)
  double frameH; // خصم ارتفاع الفرام (سم)
  double sashWExtra; // زيادة/خصم عرض الضلفة (سم)
  double sashHMinus; // خصم ارتفاع الضلفة (سم)
  double wireWExtra; // زيادة/خصم عرض السلك (سم)
  double wireHMinus; // خصم ارتفاع السلك (سم)

  SettingsModel({
    required this.frameW,
    required this.frameH,
    required this.sashWExtra,
    required this.sashHMinus,
    required this.wireWExtra,
    required this.wireHMinus,
  });

  static SettingsModel defaults() => SettingsModel(
        frameW: 0,
        frameH: 0,
        sashWExtra: 0.5, // حسب كلامك (زيادة 0.5)
        sashHMinus: 7, // حسب كلامك
        wireWExtra: 0, // السلك نفس عرض الضلفة عادة
        wireHMinus: 6, // حسب كلامك
      );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "AluUPVC Pro",
      theme: ThemeData(useMaterial3: true),
      home: const ProHome(),
    );
  }
}

class ProHome extends StatefulWidget {
  const ProHome({super.key});
  @override
  State<ProHome> createState() => _ProHomeState();
}

class _ProHomeState extends State<ProHome> {
  final _page = PageController();
  int _pageIndex = 0;

  // إدخال
  final _inputCtrl = TextEditingController();
  WinType _type = WinType.sliding2;
  bool _hasWire = true;

  // مشروع واحد
  final List<ProjectItem> _items = [];

  // إعدادات محفوظة
  SettingsModel _settings = SettingsModel.defaults();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    final d = SettingsModel.defaults();
    setState(() {
      _settings = SettingsModel(
        frameW: sp.getDouble("frameW") ?? d.frameW,
        frameH: sp.getDouble("frameH") ?? d.frameH,
        sashWExtra: sp.getDouble("sashWExtra") ?? d.sashWExtra,
        sashHMinus: sp.getDouble("sashHMinus") ?? d.sashHMinus,
        wireWExtra: sp.getDouble("wireWExtra") ?? d.wireWExtra,
        wireHMinus: sp.getDouble("wireHMinus") ?? d.wireHMinus,
      );
    });
  }

  Future<void> _saveSettings(SettingsModel m) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble("frameW", m.frameW);
    await sp.setDouble("frameH", m.frameH);
    await sp.setDouble("sashWExtra", m.sashWExtra);
    await sp.setDouble("sashHMinus", m.sashHMinus);
    await sp.setDouble("wireWExtra", m.wireWExtra);
    await sp.setDouble("wireHMinus", m.wireHMinus);
    setState(() => _settings = m);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ===== parsing صيغة 120في150في3 (سنتي) =====
  ProjectItem? _parseLine(String s) {
    final txt = s.trim().replaceAll(" ", "");
    final parts = txt.split("في");
    if (parts.length < 2) return null;

    final w = double.tryParse(_toLatinDigits(parts[0])) ?? 0;
    final h = double.tryParse(_toLatinDigits(parts[1])) ?? 0;
    final q = (parts.length >= 3) ? (int.tryParse(_toLatinDigits(parts[2])) ?? 1) : 1;

    if (w <= 0 || h <= 0 || q <= 0) return null;

    return ProjectItem(
      wCm: w,
      hCm: h,
      qty: q,
      type: _type,
      hasWire: _type.isSliding ? _hasWire : false,
    );
  }

  String _toLatinDigits(String s) {
    const ar = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    const en = ['0','1','2','3','4','5','6','7','8','9'];
    var out = s;
    for (int i = 0; i < 10; i++) {
      out = out.replaceAll(ar[i], en[i]);
    }
    return out;
  }

  void _addFromInput() {
    final item = _parseLine(_inputCtrl.text);
    if (item == null) {
      _toast("الصيغة غلط. مثال: 120في150في3");
      return;
    }
    setState(() {
      _items.add(item);
      _inputCtrl.clear();
    });
  }

  // ===== حسابات أساسية حسب اتفاقنا =====
  double _frameW(ProjectItem it) => max(0, it.wCm - _settings.frameW);
  double _frameH(ProjectItem it) => max(0, it.hCm - _settings.frameH);

  double _sashW(ProjectItem it) {
    final base = _frameW(it) / it.type.sashes;
    return max(0, base + _settings.sashWExtra);
  }

  double _sashH(ProjectItem it) => max(0, _frameH(it) - _settings.sashHMinus);

  int _wireCount(ProjectItem it) {
    if (!it.hasWire) return 0;
    // جرار 2 ضلفة -> سلك ضلفة واحدة
    // جرار 4 ضلفة -> سلك ضلفتين
    return it.type == WinType.sliding4 ? 2 : 1;
  }

  double _wireW(ProjectItem it) => max(0, _sashW(it) + _settings.wireWExtra);
  double _wireH(ProjectItem it) => max(0, _frameH(it) - _settings.wireHMinus);

  // ===== سكان: أكتر من سطر + إضافة مرة واحدة =====
  Future<void> _scanMultiLines() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x == null) return;

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(x.path);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();

      final raw = result.text.trim();
      if (raw.isEmpty) {
        _toast("ماطلعش نص. جرّب صورة أوضح/إضاءة أحسن.");
        return;
      }

      // استخراج السطور اللي فيها "في"
      final lines = raw
          .split(RegExp(r'[\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final candidates = <String>[];
      for (final l in lines) {
        if (l.contains("في")) candidates.add(l);
      }

      if (candidates.isEmpty) {
        _toast("مافيش سطور بصيغة فيها (في).");
        return;
      }

      // شاشة اختيار + تعديل سريع
      final selected = List<bool>.filled(candidates.length, true);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text("السكان (اختار السطور)"),
              content: SizedBox(
                width: double.maxFinite,
                height: 380,
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    return CheckboxListTile(
                      value: selected[i],
                      onChanged: (v) => setLocal(() => selected[i] = v ?? true),
                      title: Text(candidates[i]),
                      subtitle: const Text("مثال صحيح: 120في150في3"),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
                TextButton(
                  onPressed: () => setLocal(() {
                    for (int i = 0; i < selected.length; i++) selected[i] = true;
                  }),
                  child: const Text("تحديد الكل"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final picked = <ProjectItem>[];
                    for (int i = 0; i < candidates.length; i++) {
                      if (!selected[i]) continue;
                      final it = _parseLine(_cleanupScanLine(candidates[i]));
                      if (it != null) picked.add(it);
                    }
                    if (picked.isEmpty) {
                      _toast("السطور المختارة مش بصيغة صحيحة.");
                      return;
                    }
                    setState(() => _items.addAll(picked));
                    Navigator.pop(context);
                    _toast("تمت إضافة ${picked.length} سطر ✅");
                  },
                  child: const Text("إضافة المختار للمشروع"),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      _toast("خطأ في السكان: $e");
    }
  }

  // تنظيف بسيط لأي رموز غريبة من OCR
  String _cleanupScanLine(String s) {
    return s
        .replaceAll(" ", "")
        .replaceAll("v", "في")
        .replaceAll("V", "في");
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _pageInput(),
      _pageTable(),
      _pageResults(),
      _pageSettings(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("AluUPVC Pro"), centerTitle: true),
      body: PageView(
        controller: _page,
        onPageChanged: (i) => setState(() => _pageIndex = i),
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _pageIndex,
        onTap: (i) => _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: "إدخال"),
          BottomNavigationBarItem(icon: Icon(Icons.table_chart), label: "الجدول"),
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: "النتائج"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "الإعدادات"),
        ],
      ),
    );
  }

  Widget _pageInput() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          DropdownButtonFormField<WinType>(
            value: _type,
            items: WinType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label))).toList(),
            onChanged: (v) => setState(() {
              _type = v!;
              if (!_type.isSliding) _hasWire = false;
            }),
            decoration: const InputDecoration(labelText: "النوع", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          if (_type.isSliding)
            SwitchListTile(
              title: const Text("سلك"),
              subtitle: const Text("جرار 2: سلك ضلفة — جرار 4: سلك ضلفتين"),
              value: _hasWire,
              onChanged: (v) => setState(() => _hasWire = v),
            ),
          TextField(
            controller: _inputCtrl,
            decoration: const InputDecoration(
              labelText: "الصيغة: 120في150في3 (سم)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addFromInput,
                  icon: const Icon(Icons.add),
                  label: const Text("إضافة"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanMultiLines,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("سكان (متعدد)"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text("عدد سطور المشروع: ${_items.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _pageTable() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text("جدول المشروع", style: Theme.of(context).textTheme.titleLarge)),
              if (_items.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _items.clear()),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text("مسح الكل"),
                )
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text("لسه مافيش بيانات."))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      return Card(
                        child: ListTile(
                          title: Text("${it.wCm} × ${it.hCm} × ${it.qty} سم"),
                          subtitle: Text("${it.type.label}${it.hasWire ? " + سلك" : ""}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pageResults() {
    if (_items.isEmpty) {
      return const Center(child: Text("مفيش بيانات لسه."));
    }

    int totalSashes = 0;
    int totalWireUnits = 0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text("النتائج", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final it in _items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(builder: (_) {
                final fw = _frameW(it);
                final fh = _frameH(it);
                final sw = _sashW(it);
                final sh = _sashH(it);

                final sashCount = it.type.sashes * it.qty;
                totalSashes += sashCount;

                final wireCount = _wireCount(it) * it.qty;
                totalWireUnits += wireCount;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${it.type.label} — ${it.wCm}في${it.hCm}في${it.qty}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text("بعد خصم الفرام: ${fw.toStringAsFixed(1)} × ${fh.toStringAsFixed(1)} سم"),
                    Text("مقاس الضلفة: ${sw.toStringAsFixed(1)} × ${sh.toStringAsFixed(1)} سم"),
                    Text("عدد الضلف (إجمالي): $sashCount"),
                    if (it.hasWire)
                      Text("السلك: $wireCount | مقاسه: ${_wireW(it).toStringAsFixed(1)} × ${_wireH(it).toStringAsFixed(1)} سم"),
                  ],
                );
              }),
            ),
          ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            title: const Text("إجمالي المشروع"),
            subtitle: Text("إجمالي الضلف: $totalSashes  |  إجمالي السلك: $totalWireUnits"),
          ),
        ),
      ],
    );
  }

  Widget _pageSettings() {
    final d = SettingsModel.defaults();

    final cFrameW = TextEditingController(text: _settings.frameW.toString());
    final cFrameH = TextEditingController(text: _settings.frameH.toString());
    final cSashW = TextEditingController(text: _settings.sashWExtra.toString());
    final cSashHMinus = TextEditingController(text: _settings.sashHMinus.toString());
    final cWireW = TextEditingController(text: _settings.wireWExtra.toString());
    final cWireHMinus = TextEditingController(text: _settings.wireHMinus.toString());

    double pd(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text("الإعدادات (تتحفظ)", style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        _numField("خصم عرض الفرام (سم)", cFrameW),
        _numField("خصم ارتفاع الفرام (سم)", cFrameH),
        _numField("زيادة/خصم عرض الضلفة (سم) — مثال 0.5", cSashW),
        _numField("خصم ارتفاع الضلفة (سم) — مثال 7", cSashHMinus),
        _numField("زيادة/خصم عرض السلك (سم)", cWireW),
        _numField("خصم ارتفاع السلك (سم) — مثال 6", cWireHMinus),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () async {
            final m = SettingsModel(
              frameW: pd(cFrameW),
              frameH: pd(cFrameH),
              sashWExtra: pd(cSashW),
              sashHMinus: pd(cSashHMinus),
              wireWExtra: pd(cWireW),
              wireHMinus: pd(cWireHMinus),
            );
            await _saveSettings(m);
            _toast("تم الحفظ ✅");
          },
          icon: const Icon(Icons.save),
          label: const Text("حفظ"),
        ),
        OutlinedButton(
          onPressed: () async {
            await _saveSettings(d);
            _toast("رجعنا للافتراضي ✅");
          },
          child: const Text("افتراضي"),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
