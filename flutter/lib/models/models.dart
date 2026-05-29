// ─── User Model ───────────────────────────────────────────────────────────────

class UserModel {
  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String role;
  final bool isVerified;
  final bool phoneVerified;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    required this.role,
    required this.isVerified,
    required this.phoneVerified,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'],
        fullName: j['full_name'],
        phone: j['phone'],
        email: j['email'],
        role: j['role'],
        isVerified: j['is_verified'] ?? false,
        phoneVerified: j['phone_verified'] ?? false,
        avatarUrl: j['avatar_url'],
        createdAt: DateTime.parse(j['created_at']),
      );

  bool get isAgent => role == 'agent';
  bool get isClient => role == 'client' || role == 'business';
  bool get isAdmin => role == 'admin';
}

// ─── Agent Profile Model ──────────────────────────────────────────────────────

class AgentProfileModel {
  final String id;
  final String userId;
  final String trustLevel;
  final double trustScore;
  final int totalTasks;
  final int completedTasks;
  final double successRate;
  final double punctualityRate;
  final int repeatClientCount;
  final String? bio;
  final List<String>? skillTags;
  final bool isAvailable;
  final String? gender;
  final double yearsActive;

  const AgentProfileModel({
    required this.id,
    required this.userId,
    required this.trustLevel,
    required this.trustScore,
    required this.totalTasks,
    required this.completedTasks,
    required this.successRate,
    required this.punctualityRate,
    required this.repeatClientCount,
    this.bio,
    this.skillTags,
    required this.isAvailable,
    this.gender,
    required this.yearsActive,
  });

  factory AgentProfileModel.fromJson(Map<String, dynamic> j) => AgentProfileModel(
        id: j['id'],
        userId: j['user_id'],
        trustLevel: j['trust_level'] ?? 'bronze',
        trustScore: (j['trust_score'] ?? 0).toDouble(),
        totalTasks: j['total_tasks'] ?? 0,
        completedTasks: j['completed_tasks'] ?? 0,
        successRate: (j['success_rate'] ?? 0).toDouble(),
        punctualityRate: (j['punctuality_rate'] ?? 0).toDouble(),
        repeatClientCount: j['repeat_client_count'] ?? 0,
        bio: j['bio'],
        skillTags: j['skill_tags'] != null
            ? List<String>.from(j['skill_tags'])
            : null,
        isAvailable: j['is_available'] ?? false,
        gender: j['gender'],
        yearsActive: (j['years_active'] ?? 0).toDouble(),
      );
}

// ─── Task Model ───────────────────────────────────────────────────────────────

class TaskModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String status;
  final bool isEmergency;
  final double budget;
  final double? finalPrice;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String? destinationAddress;
  final String genderPreference;
  final bool preferredAgentsOnly;
  final String? specialInstructions;
  final String? scheduledAt;
  final String? acceptedAt;
  final String? startedAt;
  final String? completedAt;
  final DateTime createdAt;
  final String clientId;
  final String? agentId;
  final int applicationCount;
  final ClientSummaryModel? client;
  final List<ApplicationModel> applications;

  const TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.isEmergency,
    required this.budget,
    this.finalPrice,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    this.destinationAddress,
    required this.genderPreference,
    required this.preferredAgentsOnly,
    this.specialInstructions,
    this.scheduledAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    required this.clientId,
    this.agentId,
    this.applicationCount = 0,
    this.client,
    this.applications = const [],
  });

  factory TaskModel.fromJson(Map<String, dynamic> j) => TaskModel(
        id: j['id'],
        title: j['title'],
        description: j['description'],
        category: j['category'],
        status: j['status'],
        isEmergency: j['is_emergency'] ?? false,
        budget: (j['budget'] ?? 0).toDouble(),
        finalPrice: j['final_price'] != null
            ? (j['final_price']).toDouble()
            : null,
        pickupAddress: j['pickup_address'] ?? '',
        pickupLat: (j['pickup_lat'] ?? 0).toDouble(),
        pickupLng: (j['pickup_lng'] ?? 0).toDouble(),
        destinationAddress: j['destination_address'],
        genderPreference: j['gender_preference'] ?? 'any',
        preferredAgentsOnly: j['preferred_agents_only'] ?? false,
        specialInstructions: j['special_instructions'],
        scheduledAt: j['scheduled_at'],
        acceptedAt: j['accepted_at'],
        startedAt: j['started_at'],
        completedAt: j['completed_at'],
        createdAt: DateTime.parse(j['created_at']),
        clientId: j['client_id'],
        agentId: j['agent_id'],
        applicationCount: j['application_count'] ?? 0,
        client: j['client'] != null
            ? ClientSummaryModel.fromJson(j['client'])
            : null,
        applications: j['applications'] != null
            ? (j['applications'] as List)
                .map((a) => ApplicationModel.fromJson(a))
                .toList()
            : [],
      );

  bool get isActive => ['accepted', 'in_progress', 'proof_submitted'].contains(status);
  bool get isOpen => ['posted', 'agents_applied'].contains(status);
  bool get isDone => ['completed', 'cancelled', 'expired'].contains(status);

  String get statusLabel {
    switch (status) {
      case 'posted': return 'Looking for agents';
      case 'agents_applied': return 'Agents applied';
      case 'accepted': return 'Agent assigned';
      case 'in_progress': return 'In progress';
      case 'proof_submitted': return 'Awaiting confirmation';
      case 'completed': return 'Completed';
      case 'disputed': return 'Disputed';
      case 'cancelled': return 'Cancelled';
      case 'expired': return 'Expired';
      default: return status;
    }
  }

  String get categoryLabel {
    switch (category) {
      case 'shopping': return 'Shopping';
      case 'food_pickup': return 'Food Pickup';
      case 'cleaning': return 'Cleaning';
      case 'delivery': return 'Delivery';
      case 'office_errand': return 'Office Errand';
      case 'car_wash': return 'Car Wash';
      case 'document_submission': return 'Document';
      case 'pharmacy': return 'Pharmacy';
      case 'market_shopping': return 'Market';
      case 'personal_assistance': return 'Personal Help';
      case 'queue_standing': return 'Queue';
      case 'moving_items': return 'Moving';
      case 'cooking_help': return 'Cooking';
      case 'elderly_care': return 'Elderly Care';
      case 'custom': return 'Custom';
      default: return category;
    }
  }

  String get categoryEmoji {
    switch (category) {
      case 'shopping': return '🛒';
      case 'food_pickup': return '🍔';
      case 'cleaning': return '🧹';
      case 'delivery': return '📦';
      case 'office_errand': return '🏢';
      case 'car_wash': return '🚗';
      case 'document_submission': return '📄';
      case 'pharmacy': return '💊';
      case 'market_shopping': return '🏪';
      case 'personal_assistance': return '🤝';
      case 'queue_standing': return '⏳';
      case 'moving_items': return '📦';
      case 'cooking_help': return '🍳';
      case 'elderly_care': return '👴';
      default: return '✨';
    }
  }
}

class ClientSummaryModel {
  final String id;
  final String fullName;
  final String? avatarUrl;

  const ClientSummaryModel({
    required this.id,
    required this.fullName,
    this.avatarUrl,
  });

  factory ClientSummaryModel.fromJson(Map<String, dynamic> j) =>
      ClientSummaryModel(
        id: j['id'],
        fullName: j['full_name'],
        avatarUrl: j['avatar_url'],
      );
}

// ─── Application Model ────────────────────────────────────────────────────────

class ApplicationModel {
  final String id;
  final String taskId;
  final String agentId;
  final double proposedPrice;
  final String? message;
  final int? etaMinutes;
  final String status;
  final DateTime createdAt;
  final String? agentTrustLevel;
  final double? agentTrustScore;
  final int? agentCompletedTasks;
  final String? agentName;
  final String? agentAvatarUrl;

  const ApplicationModel({
    required this.id,
    required this.taskId,
    required this.agentId,
    required this.proposedPrice,
    this.message,
    this.etaMinutes,
    required this.status,
    required this.createdAt,
    this.agentTrustLevel,
    this.agentTrustScore,
    this.agentCompletedTasks,
    this.agentName,
    this.agentAvatarUrl,
  });

  factory ApplicationModel.fromJson(Map<String, dynamic> j) => ApplicationModel(
        id: j['id'],
        taskId: j['task_id'],
        agentId: j['agent_id'],
        proposedPrice: (j['proposed_price'] ?? 0).toDouble(),
        message: j['message'],
        etaMinutes: j['eta_minutes'],
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
        agentTrustLevel: j['agent_trust_level'],
        agentTrustScore: j['agent_trust_score'] != null
            ? (j['agent_trust_score']).toDouble()
            : null,
        agentCompletedTasks: j['agent_completed_tasks'],
        agentName: j['agent_name'],
        agentAvatarUrl: j['agent_avatar_url'],
      );
}

// ─── Verification Status Model ────────────────────────────────────────────────

class VerificationStatusModel {
  final String status;
  final String? rejectionReason;
  final int submissionCount;
  final DateTime submittedAt;

  const VerificationStatusModel({
    required this.status,
    this.rejectionReason,
    required this.submissionCount,
    required this.submittedAt,
  });

  factory VerificationStatusModel.fromJson(Map<String, dynamic> j) =>
      VerificationStatusModel(
        status: j['status'],
        rejectionReason: j['rejection_reason'],
        submissionCount: j['submission_count'] ?? 1,
        submittedAt: DateTime.parse(j['submitted_at']),
      );

  bool get isPending => status == 'pending' || status == 'resubmitted';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
