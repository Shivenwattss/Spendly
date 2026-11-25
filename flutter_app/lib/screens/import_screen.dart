import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool importing = false;
  String message = 'Choose a bank statement exported as CSV.';
  int? imported;

  Future<void> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.bytes == null) {
      setState(
          () => message = 'Could not read this file. Please try another CSV.');
      return;
    }
    setState(() {
      importing = true;
      message = 'Importing ${file.name}…';
      imported = null;
    });
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse('${ApiService.baseUrl}/transactions/import-csv'));
      request.files.add(http.MultipartFile.fromBytes('file', file.bytes!,
          filename: file.name));
      final streamed =
          await request.send().timeout(const Duration(seconds: 45));
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception(data is Map ? data['detail'] ?? body : body);
      }
      if (!mounted) return;
      setState(() {
        imported = (data['imported'] as num?)?.toInt() ?? 0;
        final skipped = (data['skipped'] as num?)?.toInt() ?? 0;
        message =
            'Imported $imported transactions${skipped > 0 ? ' · skipped $skipped invalid rows' : ''}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => message = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Import transactions')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.upload_file_rounded, size: 68),
                    const SizedBox(height: 20),
                    const Text('Import your bank statement',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    const Text(
                        'Upload a CSV to add transactions in one go. Spendly will categorise common merchants automatically.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 22),
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Required CSV columns',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  SizedBox(height: 6),
                                  SelectableText(
                                      'date,description,amount,type,category'),
                                  SizedBox(height: 5),
                                  Text(
                                      'Date: YYYY-MM-DD · Type: income or expense · Category is optional',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ]))),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                        onPressed: importing ? null : pickAndImport,
                        icon: const Icon(Icons.folder_open),
                        label:
                            Text(importing ? 'Importing…' : 'Choose CSV file')),
                    const SizedBox(height: 14),
                    Text(message, textAlign: TextAlign.center),
                    if (imported != null) ...[
                      const SizedBox(height: 18),
                      FilledButton.tonal(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Back to Spendly')),
                    ],
                  ]),
            ),
          ),
        ),
      );
}
