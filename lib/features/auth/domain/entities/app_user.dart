class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
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
  final String firstName;
  final String lastName;
  final DateTime birthday;
  final String preferredCurrencyCode;
  final bool notificationsEnabled;
  final int reminderDays;

  String get fullName => '$firstName $lastName'.trim();
  String get preferredCurrencySymbol =>
      currencySymbols[preferredCurrencyCode] ?? '$preferredCurrencyCode ';

  AppUser copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    DateTime? birthday,
    String? preferredCurrencyCode,
    bool? notificationsEnabled,
    int? reminderDays,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      birthday: birthday ?? this.birthday,
      preferredCurrencyCode:
          preferredCurrencyCode ?? this.preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderDays: reminderDays ?? this.reminderDays,
    );
  }
}
