import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/app_user.dart';

/// Handles Firebase Authentication and user profile creation in Firestore.
class AuthService {
  final FirebaseAuth? _authInstance;
  final FirebaseFirestore? _dbInstance;

  AuthService()
      : _authInstance = _tryInitAuth(),
        _dbInstance = _tryInitDb();

  static FirebaseAuth? _tryInitAuth() {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  static FirebaseFirestore? _tryInitDb() {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// True when Firebase was successfully initialised and is usable.
  bool get isAvailable => _authInstance != null && _dbInstance != null;

  FirebaseAuth get _auth => _authInstance!;
  FirebaseFirestore get _db => _dbInstance!;

  void _ensureAvailable() {
    if (!isAvailable) {
      throw Exception(
        'Firebase is not configured. Replace the placeholder values in '
        'firebase_options.dart with your project\'s config.',
      );
    }
  }

  Stream<User?> get authStateChanges =>
      _authInstance?.authStateChanges() ?? Stream.value(null);
  User? get currentUser => _authInstance?.currentUser;

  /// Registers a new student. Creates the Firebase Auth account and saves
  /// the profile document in Firestore using the user's UID as the doc ID.
  Future<AppUser> registerStudent({
    required String fullName,
    required String email,
    required String password,
    required String studentId,
    required String course,
    required String department,
    required int semester,
  }) async {
    _ensureAvailable();
    // Create the auth account.
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final uid = cred.user!.uid;
    final now = DateTime.now();

    final user = AppUser(
      uid: uid,
      fullName: fullName.trim(),
      email: email.trim(),
      studentId: studentId.trim(),
      course: course.trim(),
      department: department.trim(),
      semester: semester,
      role: AppConstants.roleStudent,
      createdAt: now,
      updatedAt: now,
    );

    // Save profile in Firestore. Role is always 'student' from the client;
    // security rules prevent users from elevating their own role.
    await _db.collection(AppConstants.usersCollection).doc(uid).set({
      ...user.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return user;
  }

  /// Signs in with email and password and returns the user's profile.
  Future<AppUser> signIn(String email, String password) async {
    _ensureAvailable();
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final uid = cred.user!.uid;
    final doc = await _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();

    if (!doc.exists) {
      // Auth account exists but profile doc is missing.
      throw ProfileMissingException(uid);
    }

    return AppUser.fromDoc(doc);
  }

  /// Sends a password-reset email.
  Future<void> sendPasswordReset(String email) async {
    _ensureAvailable();
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    _ensureAvailable();
    await _auth.signOut();
  }

  /// Updates the current user's password (requires recent authentication).
  Future<void> updatePassword(String newPassword) async {
    await currentUser?.updatePassword(newPassword);
  }

  /// Streams the current user's profile document from Firestore.
  Stream<AppUser?> userProfileStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  /// Fetches the current user's profile once.
  Future<AppUser?> getCurrentUserProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }
}

/// Thrown when a Firebase Auth account exists but the Firestore profile
/// document is missing.
class ProfileMissingException implements Exception {
  final String uid;
  ProfileMissingException(this.uid);

  @override
  String toString() =>
      'Your account exists but your profile data is missing. '
      'Please contact an administrator to complete your profile.';
}

/// Translates a [FirebaseAuthException] code into a user-friendly message.
String authErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'The email address is not valid.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'user-not-found':
      return 'No account found with this email.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'email-already-in-use':
      return 'An account already exists with this email.';
    case 'weak-password':
      return 'Password is too weak. Use at least 6 characters.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is not enabled.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'network-request-failed':
      return 'Network error. Check your internet connection.';
    case 'requires-recent-login':
      return 'Please log out and sign in again before updating your password.';
    default:
      return e.message ?? 'An authentication error occurred.';
  }
}

/// Translates a [FirebaseException] (Firestore/Storage) into a friendly message.
String firestoreErrorMessage(FirebaseException e) {
  switch (e.code) {
    case 'permission-denied':
      return 'You do not have permission to perform this action.';
    case 'unavailable':
      return 'Service is currently unavailable. Check your connection.';
    case 'not-found':
      return 'The requested data was not found.';
    case 'already-exists':
      return 'This record already exists.';
    case 'network-request-failed':
      return 'Network error. Check your internet connection.';
    default:
      return e.message ?? 'A database error occurred.';
  }
}
