import 'package:hive/hive.dart';

part 'meal_entry.g.dart';

@HiveType(typeId: 1)
class MealEntry extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final String inputType; // 'text', 'image'

  @HiveField(3)
  final String inputContent; // Text prompt or image path

  @HiveField(4)
  final String aiResponse; // The recipe or advice

  @HiveField(5)
  final bool isCooked;

  MealEntry({
    required this.id,
    required this.timestamp,
    required this.inputType,
    required this.inputContent,
    required this.aiResponse,
    this.isCooked = false,
  });
}
