import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

/// Сохраняет скачанный файл средствами платформы.
///
/// Отдельный файл-обёртка нужен, чтобы не размазывать вызовы
/// file_saver по экранам и держать одно место с понятным именем.
/// Сам пакет внутри разделяет нативную платформу и браузер, поэтому
/// дополнительных импортов с `dart:io` здесь не требуется.
Future<void> saveDownloadedFile(
  Uint8List bytes, {
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  // Имя и расширение передаём отдельно: file_saver склеивает их сам
  // и не допускает двойного расширения вида `report.csv.csv`.
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  final extension = dot > 0 ? fileName.substring(dot + 1) : '';

  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    fileExtension: extension,
    mimeType: MimeType.custom,
    customMimeType: mimeType,
  );
}
