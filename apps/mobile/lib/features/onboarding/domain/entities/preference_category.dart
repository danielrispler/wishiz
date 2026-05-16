class PreferenceCategory {
  const PreferenceCategory({
    required this.id,
    required this.label,
    required this.emoji,
  });

  final String id;
  final String label;
  final String emoji;

  static const List<PreferenceCategory> all = [
    PreferenceCategory(id: 'fashion', label: 'Fashion', emoji: '👗'),
    PreferenceCategory(id: 'beauty', label: 'Beauty', emoji: '💄'),
    PreferenceCategory(id: 'home', label: 'Home', emoji: '🏠'),
    PreferenceCategory(id: 'accessories', label: 'Accessories', emoji: '💍'),
    PreferenceCategory(id: 'gifts', label: 'Gifts', emoji: '🎁'),
    PreferenceCategory(id: 'travel', label: 'Travel', emoji: '✈️'),
  ];
}
