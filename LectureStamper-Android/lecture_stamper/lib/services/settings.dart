import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings, remembered between runs.
class AppSettings extends ChangeNotifier {
  static final AppSettings i = AppSettings._();
  AppSettings._();

  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  String _s(String k, String d) => _p.getString(k) ?? d;
  bool _b(String k, bool d) => _p.getBool(k) ?? d;
  double _d(String k, double d) => _p.getDouble(k) ?? d;

  void _set(String k, Object v) {
    if (v is String) _p.setString(k, v);
    if (v is bool) _p.setBool(k, v);
    if (v is double) _p.setDouble(k, v);
    if (v is int) _p.setInt(k, v);
    notifyListeners();
  }

  String get lang => _s('lang', 'en');
  set lang(String v) => _set('lang', v);

  /// topLeft | topRight | bottomLeft | bottomRight
  String get corner => _s('corner', 'topRight');
  set corner(String v) => _set('corner', v);

  /// false = pause-then-stamp (recommended)
  bool get stampWhilePlaying => _b('stampWhilePlaying', false);
  set stampWhilePlaying(bool v) => _set('stampWhilePlaying', v);

  bool get splitDefault => _b('splitDefault', false);
  set splitDefault(bool v) => _set('splitDefault', v);

  double get speed => _d('speed', 1.0);
  set speed(double v) => _set('speed', v);

  /// Sub-folder inside Movies ('' = Movies itself).
  String get exportFolder => _s('exportFolder', '');
  set exportFolder(String v) => _set('exportFolder', v);

  /// Video bitrate: 300 small, 500 balanced, 1000 sharp.
  int get videoKbps => (_p.getInt('videoKbps') ?? 500);
  set videoKbps(int v) => _set('videoKbps', v);

  // picker memory: kind is 'audio' or 'pdf'
  String sortBy(String kind) => _s('sort_$kind', 'date');
  void setSortBy(String kind, String v) => _set('sort_$kind', v);
  bool sortAsc(String kind) => _b('asc_$kind', false);
  void setSortAsc(String kind, bool v) => _set('asc_$kind', v);
  String view(String kind) => _s('view_$kind', 'folder');
  void setView(String kind, String v) => _set('view_$kind', v);
}
