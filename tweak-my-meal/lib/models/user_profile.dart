import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String cookingLevel; // Beginner, Intermediate, Advanced

  @HiveField(2)
  List<String> dietaryRestrictions; // Vegan, Gluten-Free, etc.

  @HiveField(3)
  String fitnessGoal; // Lose Weight, Gain Muscle, Maintenance

  @HiveField(4)
  List<String> allergies;

  UserProfile({
    required this.name,
    this.cookingLevel = 'Beginner',
    this.dietaryRestrictions = const [],
    this.fitnessGoal = 'Maintenance',
    this.allergies = const [],
  });
  
  UserProfile.empty() 
      : name = '', 
        cookingLevel = 'Beginner',
        dietaryRestrictions = [],
        fitnessGoal = 'Maintenance',
        allergies = [];
}
