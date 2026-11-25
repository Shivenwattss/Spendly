import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool importing = false;
  String message = '';

  Future<void> importCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    setState(() {
      importing = true;
      message = '';
    });

    try {
      final file = result.files.single;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/transactions/import-csv'),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(body);
      }

      final data = jsonDecode(body);

      if (!mounted) return;
      setState(() {
        message = 'Successfully imported ${data['imported']} transactions!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        message = 'Import failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import transactions')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.upload_file, size: 65),
              const SizedBox(height: 20),
              const Text(
                'Import your bank statement',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Upload a CSV statement to automatically add your transactions.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                onPressed: importing ? null : importCSV,
                icon: const Icon(Icons.upload),
                label: Text(
                  importing ? 'Importing...' : 'Choose CSV file',
                ),
              ),
              const SizedBox(height: 20),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
