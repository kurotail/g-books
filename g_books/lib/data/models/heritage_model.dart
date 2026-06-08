enum HeritageStatus { assigned, locked, completed }

class HeritageModel {
  final String id;
  final String name;
  final String cardImagePath;
  final HeritageStatus status;

  const HeritageModel({
    required this.id,
    required this.name,
    required this.cardImagePath,
    required this.status,
  });
}
