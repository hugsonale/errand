import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

const String _baseUrl = 'http://10.0.2.2:8000/api/v1';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_dio),
      PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        error: true,
        compact: true,
      ),
    ]);
  }

  Dio get dio => _dio;

  // ─── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final resp = await _dio.post('/auth/register', data: body);
    return resp.data;
  }

  Future<Map<String, dynamic>> verifyPhone(String phone, String code) async {
    final resp = await _dio.post('/auth/verify-phone', data: {'phone': phone, 'code': code});
    await _saveTokens(resp.data);
    return resp.data;
  }

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    final resp = await _dio.post('/auth/login', data: {'identifier': identifier, 'password': password});
    await _saveTokens(resp.data);
    return resp.data;
  }

  Future<void> resendOtp(String phone) async {
    await _dio.post('/auth/resend-otp', data: {'phone': phone});
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      try {
        await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
      } catch (_) {}
    }
    await _clearTokens();
  }

  // ─── Users ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMe() async {
    final resp = await _dio.get('/users/me');
    return resp.data;
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> body) async {
    final resp = await _dio.patch('/users/me', data: body);
    return resp.data;
  }

  // ─── Agents ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> submitKyc(FormData formData) async {
    final resp = await _dio.post('/agents/verify/submit', data: formData);
    return resp.data;
  }

  Future<Map<String, dynamic>> getVerificationStatus() async {
    final resp = await _dio.get('/agents/verify/status');
    return resp.data;
  }

  Future<Map<String, dynamic>> getMyAgentProfile() async {
    final resp = await _dio.get('/agents/me/profile');
    return resp.data;
  }

  Future<void> updateLocation(double lat, double lng) async {
    await _dio.patch('/agents/location', data: {'latitude': lat, 'longitude': lng});
  }

  Future<Map<String, dynamic>> toggleAvailability(bool isAvailable) async {
    final resp = await _dio.patch('/agents/availability', data: {'is_available': isAvailable});
    return resp.data;
  }

  Future<Map<String, dynamic>> getAgentProfile(String agentId) async {
    final resp = await _dio.get('/agents/$agentId/profile');
    return resp.data;
  }

  Future<List<dynamic>> getNearbyAgents(double lat, double lng, {double radiusKm = 5.0}) async {
    final resp = await _dio.get('/tasks/nearby-agents', queryParameters: {
      'lat': lat, 'lng': lng, 'radius_km': radiusKm,
    });
    return resp.data;
  }

  // ─── Tasks ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createTask(Map<String, dynamic> body) async {
    final resp = await _dio.post('/tasks/', data: body);
    return resp.data;
  }

  Future<Map<String, dynamic>> listTasks({
    String? category, String? status, bool? isEmergency,
    double? lat, double? lng, double radiusKm = 10.0,
    double? minBudget, double? maxBudget,
    int page = 1, int pageSize = 20,
  }) async {
    final resp = await _dio.get('/tasks/', queryParameters: {
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (isEmergency != null) 'is_emergency': isEmergency,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'radius_km': radiusKm,
      if (minBudget != null) 'min_budget': minBudget,
      if (maxBudget != null) 'max_budget': maxBudget,
      'page': page,
      'page_size': pageSize,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> getTask(String taskId) async {
    final resp = await _dio.get('/tasks/$taskId');
    return resp.data;
  }

  Future<Map<String, dynamic>> applyToTask(String taskId, Map<String, dynamic> body) async {
    final resp = await _dio.post('/tasks/$taskId/apply', data: body);
    return resp.data;
  }

  Future<Map<String, dynamic>> acceptApplication(String taskId, String applicationId) async {
    final resp = await _dio.post('/tasks/$taskId/accept/$applicationId');
    return resp.data;
  }

  Future<Map<String, dynamic>> startTask(String taskId) async {
    final resp = await _dio.post('/tasks/$taskId/start');
    return resp.data;
  }

  Future<Map<String, dynamic>> submitProof(String taskId, FormData formData) async {
    final resp = await _dio.post('/tasks/$taskId/complete', data: formData);
    return resp.data;
  }

  Future<Map<String, dynamic>> confirmCompletion(String taskId, {String? otpCode}) async {
    final resp = await _dio.post('/tasks/$taskId/confirm', data: {
      if (otpCode != null) 'otp_code': otpCode,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> cancelTask(String taskId) async {
    final resp = await _dio.delete('/tasks/$taskId');
    return resp.data;
  }

  Future<Map<String, dynamic>> raiseDispute(String taskId, Map<String, dynamic> body) async {
    final resp = await _dio.post('/tasks/$taskId/dispute', data: body);
    return resp.data;
  }

  // ─── Payments ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> initiatePayment(String taskId) async {
    final resp = await _dio.post('/payments/initiate/$taskId');
    return resp.data;
  }

  Future<Map<String, dynamic>> getPaymentHistory({int page = 1}) async {
    final resp = await _dio.get('/payments/history', queryParameters: {'page': page});
    return resp.data;
  }

  // ─── Reviews ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> submitReview(Map<String, dynamic> body) async {
    final resp = await _dio.post('/reviews/', data: body);
    return resp.data;
  }

  Future<Map<String, dynamic>> getAgentReviews(String agentUserId, {int page = 1}) async {
    final resp = await _dio.get('/reviews/agent/$agentUserId', queryParameters: {'page': page});
    return resp.data;
  }

  Future<Map<String, dynamic>> getTrustScore(String agentUserId) async {
    final resp = await _dio.get('/reviews/trust-score/$agentUserId');
    return resp.data;
  }

  // ─── Notifications ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getNotifications({bool unreadOnly = false}) async {
    final resp = await _dio.get('/notifications/', queryParameters: {
      if (unreadOnly) 'unread_only': true,
    });
    return resp.data;
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _dio.post('/notifications/$notificationId/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _dio.post('/notifications/read-all');
  }

  // ─── Token helpers ─────────────────────────────────────────────────────────

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(key: 'access_token', value: data['access_token']);
    await _storage.write(key: 'refresh_token', value: data['refresh_token']);
  }

  Future<void> _clearTokens() async {
    await _storage.deleteAll();
  }

  static Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  static Future<String?> getRefreshToken() => _storage.read(key: 'refresh_token');
}

// ─── Auth Interceptor ─────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final Dio dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this.dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await ApiService.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await ApiService.getRefreshToken();
        if (refreshToken == null) {
          _isRefreshing = false;
          handler.next(err);
          return;
        }
        final resp = await Dio(BaseOptions(baseUrl: _baseUrl))
            .post('/auth/refresh', data: {'refresh_token': refreshToken});
        await _storage.write(key: 'access_token', value: resp.data['access_token']);
        await _storage.write(key: 'refresh_token', value: resp.data['refresh_token']);
        err.requestOptions.headers['Authorization'] = 'Bearer ${resp.data['access_token']}';
        final retried = await dio.fetch(err.requestOptions);
        handler.resolve(retried);
      } catch (_) {
        await _storage.deleteAll();
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}

// ─── Global singleton ─────────────────────────────────────────────────────────

final apiService = ApiService();