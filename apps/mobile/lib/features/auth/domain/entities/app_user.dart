import 'package:wishiz/core/utils/currency_utils.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.birthday,
    this.gender,
    this.preferredCurrencyCode = 'USD',
    this.notificationsEnabled = true,
    this.reminderDays = 14,
    this.preferredBrands = const [],
  });

  static const List<String> supportedCurrencyCodes = [
    'USD',
    'EUR',
    'GBP',
    'ILS',
  ];
  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'ILS': '₪',
  };
  static const List<String> supportedGenders = ['woman', 'man'];

  final String id;
  final String email;
  final String fullName;
  final DateTime birthday;
  final String? gender;
  final String preferredCurrencyCode;
  final bool notificationsEnabled;
  final int reminderDays;
  final List<String> preferredBrands;

  String get preferredCurrencySymbol =>
      CurrencyUtils.symbolFor(preferredCurrencyCode);

  static String genderLabel(String value) {
    switch (value) {
      case 'woman':
        return 'Woman';
      case 'man':
        return 'Man';
      default:
        return value;
    }
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? fullName,
    DateTime? birthday,
    String? gender,
    String? preferredCurrencyCode,
    bool? notificationsEnabled,
    int? reminderDays,
    List<String>? preferredBrands,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      birthday: birthday ?? this.birthday,
      gender: gender ?? this.gender,
      preferredCurrencyCode:
          preferredCurrencyCode ?? this.preferredCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderDays: reminderDays ?? this.reminderDays,
      preferredBrands: preferredBrands ?? this.preferredBrands,
    );
  }
}
