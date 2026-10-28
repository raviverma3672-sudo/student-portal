
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/timetable_provider.dart';
import 'providers/assignment_provider.dart';
import 'providers/notice_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('Firebase initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('Firebase initialization failed: $e');
    debugPrintStack(stackTrace: stackTrace);
    rethrow;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => TimetableProvider()),
        ChangeNotifierProvider(create: (_) => AssignmentProvider()),
        ChangeNotifierProvider(create: (_) => NoticeProvider()),
      ],
      child: const CampusConnectApp(),
    ),
  );
}
