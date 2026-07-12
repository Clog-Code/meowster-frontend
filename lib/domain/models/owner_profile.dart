class OwnerProfile {
  const OwnerProfile({
    required this.name,
    required this.phone,
    required this.address,
  });

  final String name;
  final String phone;
  final String address;

  Map<String, dynamic> toJson() => {
        'owner_name': name,
        'owner_phone': phone,
        'owner_address': address,
      };
}
