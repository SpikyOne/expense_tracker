import 'package:dbus/dbus.dart';

/// Системный диалог «Поделиться» ОС Аврора.
/// Вызывает DBus-службу org.sailfishos.share — тот же путь,
/// что использует официальный плагин share_plus_aurora (ОМП).
class ShareService {
  /// Поделиться файлом (например, сохранённым MD-отчётом).
  static Future<bool> shareFile(String path, {String? title, String? mimeType}) async {
    final resources = <DBusValue>[];
    final name = path.split('/').last;
    final optionals = <String, DBusValue>{'name': DBusString(name)};
    if (mimeType != null) {
      optionals['data'] = DBusString(mimeType);
    }
    resources.add(DBusString(path));
    resources.add(DBusDict.stringVariant(optionals));
    final params = <String, DBusValue>{
      'selectedTransferMethodInfo': DBusArray.variant([]),
      'resources': DBusArray.variant(resources),
    };
    if (title != null) {
      params['title'] = DBusString(title);
    }
    return _invoke(params);
  }

  /// Поделиться текстом (самим содержимым MD-отчёта).
  static Future<bool> shareText(String text, {String? title}) async {
    const mime = DBusString('text/plain');
    final resources = <DBusValue>[
      DBusDict.stringVariant({
        'type': mime,
        'name': DBusString(text),
        'data': DBusString(text),
        'status': DBusString(text),
      }),
    ];
    final params = <String, DBusValue>{
      'selectedTransferMethodInfo': DBusArray.variant([]),
      'resources': DBusArray.variant(resources),
      'mimeType': mime,
    };
    if (title != null) {
      params['title'] = DBusString(title);
    }
    return _invoke(params);
  }

  static Future<bool> _invoke(Map<String, DBusValue> params) async {
    DBusClient? client;
    try {
      client = DBusClient.session();
      final object = DBusRemoteObject(
        client,
        name: 'org.sailfishos.share',
        path: const DBusObjectPath.unchecked('/'),
      );
      await object.callMethod('org.sailfishos.share', 'share', [
        DBusDict.stringVariant(params),
      ]);
      await client.close();
      return true;
    } catch (_) {
      try {
        await client?.close();
      } catch (_) {}
      return false;
    }
  }
}
