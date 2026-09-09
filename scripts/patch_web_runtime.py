from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"anchor missing in {path}: {old[:80]!r}")
    p.write_text(text.replace(old, new, 1))


# Browser document upload: web FilePicker has bytes, not a filesystem path.
path = "flutter-app/lib/screens/tools/erp_tools_screen.dart"
replace_once(
    path,
    "import 'package:file_picker/file_picker.dart';\nimport 'package:flutter/material.dart';",
    "import 'package:file_picker/file_picker.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
)

p = Path(path)
text = p.read_text()
start = text.index("  Future<void> _uploadDocument(int employeeId) async {")
end = text.index(
    "  Future<List<Map<String, dynamic>>> _employeeChoices() async {", start
)
new_upload = '''  Future<void> _uploadDocument(int employeeId) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: kIsWeb,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (!kIsWeb && file.path == null) return;
    if (kIsWeb && file.bytes == null) {
      _msg('Browser could not read the selected file. Please select it again.');
      return;
    }
    final type = TextEditingController(text: 'employee_document');
    final title = TextEditingController(text: file.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Employee Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: type,
              decoration: const InputDecoration(labelText: 'Document Type'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        final api = ref.read(apiClientProvider);
        final fields = {
          'document_type': type.text.trim(),
          'title': title.text.trim(),
        };
        if (kIsWeb) {
          await api.uploadBytes(
            ApiPaths.employeeDocumentUpload(employeeId),
            bytes: file.bytes!,
            filename: file.name,
            fields: fields,
          );
        } else {
          await api.uploadFile(
            ApiPaths.employeeDocumentUpload(employeeId),
            filePath: file.path!,
            filename: file.name,
            fields: fields,
          );
        }
        _msg('Document uploaded.');
        if (mounted) setState(() => refresh++);
      } catch (e) {
        _msg(UiError.message(e));
      }
    }
    type.dispose();
    title.dispose();
  }

'''
p.write_text(text[:start] + new_upload + text[end:])

# Laptop/tablet Chrome should use the desktop workspace at practical widths.
replace_once(
    "flutter-app/lib/shell/app_shell.dart",
    "final desktop = constraints.maxWidth >= 1100;",
    "final desktop = constraints.maxWidth >= 960;",
)

# Use current Geolocator settings API for attendance location on Web/Android.
replace_once(
    "flutter-app/lib/screens/my_work/my_work_screen.dart",
    "return Geolocator.getCurrentPosition(\n      desiredAccuracy: LocationAccuracy.high,\n    );",
    "return Geolocator.getCurrentPosition(\n      locationSettings: const LocationSettings(\n        accuracy: LocationAccuracy.high,\n        timeLimit: Duration(seconds: 20),\n      ),\n    );",
)

# Assertions: fail closed if the intended patch did not land.
checks = {
    "flutter-app/lib/screens/tools/erp_tools_screen.dart": [
        "withData: kIsWeb",
        "api.uploadBytes",
        "package:flutter/foundation.dart",
    ],
    "flutter-app/lib/shell/app_shell.dart": [
        "constraints.maxWidth >= 960",
    ],
    "flutter-app/lib/screens/my_work/my_work_screen.dart": [
        "locationSettings: const LocationSettings",
    ],
}
for file, needles in checks.items():
    content = Path(file).read_text()
    for needle in needles:
        if needle not in content:
            raise SystemExit(f"patch assertion failed: {file}: {needle}")

print("web runtime patch assertions PASS")
