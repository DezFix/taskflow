/// Выбор и загрузка файлов: фотоотчёты и вложения.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// Расширения, которые сервер принимает: остальное лучше не предлагать.
const List<String> kAllowedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'txt',
  'log',
  'md',
  'zip',
];

/// Тип MIME по расширению: сервер сверяется с содержимым, но подсказка помогает.
String mimeTypeFor(String filename) {
  final ext =
      filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'txt' || 'log' || 'md' => 'text/plain',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

/// Загружает выбранные файлы и возвращает созданные вложения.
Future<List<Attachment>> uploadFiles(
  WidgetRef ref, {
  required List<({String name, Uint8List bytes})> files,
  String? taskId,
}) async {
  final repository = ref.read(tasksRepositoryProvider);
  final uploaded = <Attachment>[];

  for (final file in files) {
    if (file.bytes.isEmpty) continue;
    try {
      uploaded.add(
        await repository.upload(
          file: UploadFile(
            name: file.name,
            bytes: file.bytes,
            mimeType: mimeTypeFor(file.name),
          ),
          taskId: taskId,
        ),
      );
    } on ApiException catch (error) {
      ref.read(appErrorBusProvider).show(error.message);
    }
  }
  return uploaded;
}

/// Диалог выбора: фотографии с камеры, из галереи или произвольный файл.
Future<List<({String name, Uint8List bytes})>?> pickFiles(
  BuildContext context, {
  bool allowImages = true,
}) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allowImages) ...[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Выбрать файл'),
            onTap: () => Navigator.of(sheetContext).pop('file'),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Документ или фото'),
            onTap: () => Navigator.of(sheetContext).pop('document'),
          ),
        ],
      ),
    ),
  );

  if (source == null || !context.mounted) return null;

  try {
    switch (source) {
      case 'camera':
        final picker = ImagePicker();
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          // Фотоотчёты несут детали, поэтому сжимаем умеренно.
          imageQuality: 82,
          maxWidth: 1920,
        );
        if (photo == null) return null;
        return [
          (
            name: photo.name,
            bytes: await photo.readAsBytes(),
          ),
        ];

      case 'gallery':
        final picker = ImagePicker();
        final images = await picker.pickMultiImage(imageQuality: 82);
        if (images.isEmpty) return null;
        final result = <({String name, Uint8List bytes})>[];
        for (final image in images) {
          result.add((name: image.name, bytes: await image.readAsBytes()));
        }
        return result;

      case 'document':
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: kAllowedExtensions,
        );
        if (result.isEmpty) return null;
        return await _toFiles(result);

      case 'file':
      default:
        final result = await FilePicker.pickFiles();
        if (result.isEmpty) return null;
        return await _toFiles(result);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'Не удалось открыть файл: $error',
          ),
        ),
      );
    }
    return null;
  }
}

Future<List<({String name, Uint8List bytes})>> _toFiles(
  List<PlatformFile> files,
) async {
  final result = <({String name, Uint8List bytes})>[];
  for (final file in files) {
    // Содержимое читаем сами: в file_picker 13 байты больше не лежат
    // в объекте сразу, есть отдельный метод.
    result.add((name: file.name, bytes: await file.readAsBytes()));
  }
  return result;
}

/// Выбирает фотографии и сразу загружает их как вложения задачи.
Future<List<Attachment>> pickAndUploadImages(
  BuildContext context,
  WidgetRef ref, {
  String? taskId,
}) async {
  final picked = await pickFiles(context);
  if (picked == null || picked.isEmpty) return const [];
  return uploadFiles(ref, files: picked, taskId: taskId);
}
