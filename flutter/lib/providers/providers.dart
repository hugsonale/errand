import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';
import '../services/api_service.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

// ─── Auth State ───────────────────────────────────────────────────────────────

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool? isLoading,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await ApiService.getAccessToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final data = await apiService.getMe();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: UserModel.fromJson(data),
      );
    } catch (_) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> register({
    required String fullName,
    required String phone,
    required String password,
    required String role,
    String? email,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await apiService.register({
        'full_name': fullName,
        'phone': phone,
        'password': password,
        'role': role,
        if (email != null) 'email': email,
      });
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> verifyPhone(String phone, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await apiService.verifyPhone(phone, code);
      final userData = await apiService.getMe();
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.authenticated,
        user: UserModel.fromJson(userData),
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> login(String identifier, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await apiService.login(identifier, password);
      final userData = await apiService.getMe();
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.authenticated,
        user: UserModel.fromJson(userData),
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    await apiService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(error: null);

  String _parseError(dynamic e) {
    if (e is Exception) {
      final msg = e.toString();
      if (msg.contains('detail')) {
        final match = RegExp(r'"detail":"([^"]+)"').firstMatch(msg);
        if (match != null) return match.group(1)!;
      }
      if (msg.contains('DioException')) return 'Network error. Check your connection.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

// ─── Task List State ───────────────────────────────────────────────────────────

class TaskListState {
  final List<TaskModel> tasks;
  final bool isLoading;
  final String? error;
  final int page;
  final bool hasMore;

  const TaskListState({
    this.tasks = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
  });

  TaskListState copyWith({
    List<TaskModel>? tasks,
    bool? isLoading,
    String? error,
    int? page,
    bool? hasMore,
  }) =>
      TaskListState(
        tasks: tasks ?? this.tasks,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
      );
}

class TaskListNotifier extends StateNotifier<TaskListState> {
  TaskListNotifier() : super(const TaskListState());

  Future<void> loadTasks({
    String? category,
    bool? isEmergency,
    double? lat,
    double? lng,
    bool refresh = false,
  }) async {
    if (state.isLoading) return;
    if (refresh) state = const TaskListState();

    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await apiService.listTasks(
        category: category,
        isEmergency: isEmergency,
        lat: lat,
        lng: lng,
        page: refresh ? 1 : state.page,
      );
      final newTasks = (data['tasks'] as List)
          .map((t) => TaskModel.fromJson(t))
          .toList();
      state = state.copyWith(
        tasks: refresh ? newTasks : [...state.tasks, ...newTasks],
        isLoading: false,
        page: refresh ? 2 : state.page + 1,
        hasMore: data['has_more'] ?? false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load tasks. Pull to refresh.',
      );
    }
  }
}

final taskListProvider =
    StateNotifierProvider<TaskListNotifier, TaskListState>(
  (ref) => TaskListNotifier(),
);

// ─── Single Task State ────────────────────────────────────────────────────────

final taskDetailProvider =
    FutureProvider.family<TaskModel, String>((ref, taskId) async {
  final data = await apiService.getTask(taskId);
  return TaskModel.fromJson(data);
});

// ─── Agent Profile State ──────────────────────────────────────────────────────

class AgentProfileState {
  final AgentProfileModel? profile;
  final bool isLoading;
  final String? error;

  const AgentProfileState({
    this.profile,
    this.isLoading = false,
    this.error,
  });

  AgentProfileState copyWith({
    AgentProfileModel? profile,
    bool? isLoading,
    String? error,
  }) =>
      AgentProfileState(
        profile: profile ?? this.profile,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AgentProfileNotifier extends StateNotifier<AgentProfileState> {
  AgentProfileNotifier() : super(const AgentProfileState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await apiService.getMyAgentProfile();
      state = state.copyWith(
        profile: AgentProfileModel.fromJson(data),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> toggleAvailability(bool isAvailable) async {
    try {
      final data = await apiService.toggleAvailability(isAvailable);
      state = state.copyWith(profile: AgentProfileModel.fromJson(data));
      return true;
    } catch (_) {
      return false;
    }
  }
}

final agentProfileProvider =
    StateNotifierProvider<AgentProfileNotifier, AgentProfileState>(
  (ref) => AgentProfileNotifier(),
);

// ─── Task Post State ──────────────────────────────────────────────────────────

class PostTaskState {
  final int step;
  final String? category;
  final String? title;
  final String? description;
  final String? specialInstructions;
  final bool isEmergency;
  final double budget;
  final String? pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String? destinationAddress;
  final String genderPreference;
  final bool isLoading;
  final String? error;

  const PostTaskState({
    this.step = 1,
    this.category,
    this.title,
    this.description,
    this.specialInstructions,
    this.isEmergency = false,
    this.budget = 2000,
    this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    this.destinationAddress,
    this.genderPreference = 'any',
    this.isLoading = false,
    this.error,
  });

  PostTaskState copyWith({
    int? step,
    String? category,
    String? title,
    String? description,
    String? specialInstructions,
    bool? isEmergency,
    double? budget,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? destinationAddress,
    String? genderPreference,
    bool? isLoading,
    String? error,
  }) =>
      PostTaskState(
        step: step ?? this.step,
        category: category ?? this.category,
        title: title ?? this.title,
        description: description ?? this.description,
        specialInstructions: specialInstructions ?? this.specialInstructions,
        isEmergency: isEmergency ?? this.isEmergency,
        budget: budget ?? this.budget,
        pickupAddress: pickupAddress ?? this.pickupAddress,
        pickupLat: pickupLat ?? this.pickupLat,
        pickupLng: pickupLng ?? this.pickupLng,
        destinationAddress: destinationAddress ?? this.destinationAddress,
        genderPreference: genderPreference ?? this.genderPreference,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class PostTaskNotifier extends StateNotifier<PostTaskState> {
  PostTaskNotifier() : super(const PostTaskState());

  void setCategory(String category) =>
      state = state.copyWith(step: 2, category: category);

  void setDetails({
    required String title,
    required String description,
    String? specialInstructions,
    String? pickupAddress,
    double? lat,
    double? lng,
  }) =>
      state = state.copyWith(
        step: 3,
        title: title,
        description: description,
        specialInstructions: specialInstructions,
        pickupAddress: pickupAddress,
        pickupLat: lat,
        pickupLng: lng,
      );

  void setBudget({
    required double budget,
    required bool isEmergency,
    required String genderPreference,
  }) =>
      state = state.copyWith(
        step: 4,
        budget: budget,
        isEmergency: isEmergency,
        genderPreference: genderPreference,
      );

  void goToReview() => state = state.copyWith(step: 5);
  void goBack() => state = state.copyWith(step: state.step - 1);
  void reset() => state = const PostTaskState();

  Future<TaskModel?> submit() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await apiService.createTask({
        'title': state.title,
        'description': state.description,
        'category': state.category,
        'special_instructions': state.specialInstructions,
        'is_emergency': state.isEmergency,
        'budget': state.budget,
        'pickup_address': state.pickupAddress ?? 'Lagos, Nigeria',
        'pickup_lat': state.pickupLat ?? 6.5244,
        'pickup_lng': state.pickupLng ?? 3.3792,
        'gender_preference': state.genderPreference,
      });
      state = state.copyWith(isLoading: false);
      return TaskModel.fromJson(data);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }
}

final postTaskProvider =
    StateNotifierProvider<PostTaskNotifier, PostTaskState>(
  (ref) => PostTaskNotifier(),
);
