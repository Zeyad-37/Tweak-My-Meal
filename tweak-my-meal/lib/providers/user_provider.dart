import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_profile.dart';

class UserProvider extends ChangeNotifier {
  Box? _box;
  UserProfile? _userProfile;

  UserProfile? get userProfile => _userProfile;
  bool get hasProfile => _userProfile != null && _userProfile!.name.isNotEmpty;

  UserProvider() {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox('user_prefs');
    if (_box!.containsKey('profile')) {
      // In a real app we'd use the generated adapter
      // _userProfile = _box!.get('profile');
      
      // For this hackathon step without build_runner yet:
      // We will perform a simple check or manual read if adapter fails
      // But let's assume valid state for now.
    }
    notifyListeners();
  }

  Future<void> saveProfile(UserProfile profile) async {
    _userProfile = profile;
    if (_box == null) await _init();
    
    await _box!.put('profile_name', profile.name);
    await _box!.put('cooking_level', profile.cookingLevel);
    await _box!.put('restrictions', profile.dietaryRestrictions);
    await _box!.put('goals', profile.fitnessGoal);
    await _box!.put('completed_onboarding', true);
    
    notifyListeners();
  }
}
