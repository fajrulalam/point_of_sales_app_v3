/// Model for an association rule from the CSV
class AssociationRule {
  final int id;
  final List<String> antecedents; // Items that trigger the recommendation
  final List<String> consequents; // Items to recommend
  final double confidence;
  final double support;
  final double lift;

  AssociationRule({
    required this.id,
    required this.antecedents,
    required this.consequents,
    required this.confidence,
    required this.support,
    required this.lift,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'antecedents': antecedents.join('|'),
      'consequents': consequents.join('|'),
      'confidence': confidence,
      'support': support,
      'lift': lift,
    };
  }

  factory AssociationRule.fromMap(Map<String, dynamic> map) {
    return AssociationRule(
      id: map['id'] as int,
      antecedents: (map['antecedents'] as String).split('|'),
      consequents: (map['consequents'] as String).split('|'),
      confidence: map['confidence'] as double,
      support: map['support'] as double,
      lift: map['lift'] as double,
    );
  }

  @override
  String toString() {
    return 'Rule: ${antecedents.join(", ")} -> ${consequents.join(", ")} (conf: ${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

/// Model for a recommendation to show to user
class Recommendation {
  final String itemName;
  final double confidence;
  final List<String> basedOn; // Which items triggered this recommendation
  final String ruleDescription;

  Recommendation({
    required this.itemName,
    required this.confidence,
    required this.basedOn,
    required this.ruleDescription,
  });

  @override
  String toString() {
    return '$itemName (${(confidence * 100).toStringAsFixed(1)}% confidence) - Based on: ${basedOn.join(", ")}';
  }
}

/// Configuration for the recommendation system
class RecommendationConfig {
  final String version;
  final String csvFileName;
  final double matchThreshold;
  final double minConfidence;
  final int maxRecommendations;
  final bool enabled;
  final DateTime lastUpdated;

  RecommendationConfig({
    required this.version,
    required this.csvFileName,
    required this.matchThreshold,
    required this.minConfidence,
    required this.maxRecommendations,
    required this.enabled,
    required this.lastUpdated,
  });

  factory RecommendationConfig.fromFirestore(Map<String, dynamic> data) {
    return RecommendationConfig(
      version: data['version'] as String? ?? '1.0.0',
      csvFileName: data['csvFileName'] as String? ?? 'rules_filtered.csv',
      matchThreshold: (data['matchThreshold'] as num?)?.toDouble() ?? 1.0,
      minConfidence: (data['minConfidence'] as num?)?.toDouble() ?? 0.5,
      maxRecommendations: data['maxRecommendations'] as int? ?? 5,
      enabled: data['enabled'] as bool? ?? true,
      lastUpdated: data['lastUpdated'] != null
          ? DateTime.parse(data['lastUpdated'].toString())
          : DateTime.now(),
    );
  }

  factory RecommendationConfig.defaultConfig() {
    return RecommendationConfig(
      version: '1.0.0',
      csvFileName: 'rules_filtered.csv',
      matchThreshold: 0,
      minConfidence: 0.5,
      maxRecommendations: 5,
      enabled: true,
      lastUpdated: DateTime.now(),
    );
  }
}
