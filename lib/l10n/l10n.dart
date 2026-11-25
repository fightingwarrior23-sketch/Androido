import 'package:flutter/foundation.dart';
import 'strings_ar.dart';

/// English text is the key; Arabic comes from [arStrings]. {slots} are filled from args.
class L10n extends ChangeNotifier {
  static final L10n i = L10n._();
  L10n._();

  String lang = 'en';
  bool get isAr => lang == 'ar';

  void setLang(String l) {
    if (l == lang) return;
    lang = l;
    notifyListeners();
  }

  String t(String key, [Map<String, Object> args = const {}]) {
    var s = isAr ? (arStrings[key] ?? key) : key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

String tr(String key, [Map<String, Object> args = const {}]) => L10n.i.t(key, args);
