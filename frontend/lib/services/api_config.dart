class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'MEDBUDDY_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1/medication',
  );
}
