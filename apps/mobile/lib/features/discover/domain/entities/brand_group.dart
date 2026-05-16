class BrandGroup {
  final String label;
  final List<String> brands;

  const BrandGroup({required this.label, required this.brands});

  static const List<BrandGroup> all = [
    BrandGroup(label: 'High Street', brands: [
      'Zara', 'H&M', 'Mango', 'ASOS', 'COS', 'Massimo Dutti',
      'Uniqlo', 'Pull&Bear', 'Stradivarius', 'Urban Outfitters',
      'Old Navy', 'Terminal X',
    ]),
    BrandGroup(label: 'Activewear', brands: [
      'Lululemon', 'Alo Yoga', 'Nike', 'Adidas', 'New Balance',
      'Asics', 'Under Armour', 'Gymshark', 'Set Active', 'Oysho',
      'Girlfriend Collective', 'Bandit', 'CRZ Yoga',
    ]),
    BrandGroup(label: 'Premium', brands: [
      'Revolve', 'Reformation', 'Aritzia', 'Shopbop', 'Anthropologie',
      'Nordstrom', 'Factory 54', 'Story', 'De Rococo',
    ]),
    BrandGroup(label: 'Intimates & Lounge', brands: [
      'Skims', "Victoria's Secret", 'Aerie', 'Intimissimi',
    ]),
    BrandGroup(label: 'Denim & Niche', brands: [
      "Levi's", 'Pistola', 'Eloquii', 'Good American',
    ]),
  ];
}
