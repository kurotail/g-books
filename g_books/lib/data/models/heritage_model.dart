enum HeritageStatus { assigned, locked, completed }

class HeritageModel {
  final String id;
  final String name;
  final String subtitle;
  final String description;
  final String cardImagePath;
  final HeritageStatus status;

  const HeritageModel({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.description,
    required this.cardImagePath,
    required this.status,
  });
}
