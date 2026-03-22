import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drug_info.dart';

class ApiService {
  // 에뮬레이터 기준 로컬호스트 주소. (iOS 시뮬레이터는 127.0.0.1 사용)
  final String baseUrl = 'http://10.0.2.2:8000/api/v1/medication';

  Future<List<DrugInfo>> identifyMedication(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/identify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'extracted_text': text}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['success'] == true) {
          final List<dynamic> items = data['data'];
          return items.map((item) => DrugInfo.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      print('API 통신 에러: $e');
      return [];
    }
  }
}