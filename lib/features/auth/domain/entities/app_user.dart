class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.birthday,
    this.preferredCurrencyCode = 'USD',
    this.notificationsEnabled = true,
    this.reminderDays = 14,
  });

  static const List<String> supportedCurrencyCodes = [
    'USD',
    'EUR',
    'GBP',
    'ILS',
  ];
  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': 'EUR ',
    'GBP': 'GBP ',
    'ILS': 'ILS ',
  };

  final String id;
  final String email;
  final String fullName;
  final DateTime birthday;
  final String preferredCurrencyCode;
  final bool notificationsEnabled;
  final int reminderDays;

  String get preferredCurrencySymbol =>
      currencySymbols[preferredCurrencyCode] ?? '$preferredCurrencyCode ';

  AppUser copyWith({
    String? id,
    String? email,
    String? fullName,
    DateTime? birthday,
    String? preferredCurrencyCode,
    bool? notificationsEnabled,
    int? reminderDays,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      birthday: birthday ?? this.birthday,
      preferredCurrencyCode:
          preferredCurrencyCode ?? this.preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderDays: reminderDays ?? this.reminderDays,
    );
  }
}
