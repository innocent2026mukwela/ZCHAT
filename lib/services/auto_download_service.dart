import 'package:shared_preferences/shared_preferences.dart';

/// Auto-download preference: 'always', 'wifi_only', 'never'
class AutoDownloadService {
  static const _kImages = 'auto_dl_images';
  static const _kVideos = 'auto_dl_videos';
  static const _kDocs   = 'auto_dl_docs';

  static Future<String> getImages() async =>
      (await SharedPreferences.getInstance()).getString(_kImages) ?? 'always';

  static Future<String> getVideos() async =>
      (await SharedPreferences.getInstance()).getString(_kVideos) ?? 'wifi_only';

  static Future<String> getDocs() async =>
      (await SharedPreferences.getInstance()).getString(_kDocs) ?? 'always';

  static Future<void> setImages(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kImages, v);

  static Future<void> setVideos(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kVideos, v);

  static Future<void> setDocs(String v) async =>
      (await SharedPreferences.getInstance()).setString(_kDocs, v);
}
