import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants/app_constants.dart';
import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/timetable_entry.dart';
import '../models/assignment.dart';
import '../models/assignment_submission.dart';
import '../models/notice.dart';
import '../models/subject.dart';

/// Central Firestore data access layer for all collections.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Users ────────────────────────────────────────────────────────────────

  /// Streams a single user's profile by UID.
  Stream<AppUser?> userStream(String uid) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);
  }

  /// Gets a user profile once.
  Future<AppUser?> getUser(String uid) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }

  /// Updates the current user's profile. Role is intentionally excluded.
  Future<void> updateUserProfile({
    required String uid,
    String? fullName,
    String? course,
    String? department,
    int? semester,
    String? profileImageUrl,
    String? phone,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (fullName != null) updates['fullName'] = fullName;
    if (course != null) updates['course'] = course;
    if (department != null) updates['department'] = department;
    if (semester != null) updates['semester'] = semester;
    if (profileImageUrl != null) updates['profileImageUrl'] = profileImageUrl;
    if (phone != null) updates['phone'] = phone;

    await _db.collection(AppConstants.usersCollection).doc(uid).update(updates);
  }

  /// Streams all registered students (admin only).
  Stream<List<AppUser>> studentsStream() {
    return _db
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleStudent)
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromDoc).toList());
  }

  /// Streams all users (admin only).
  Stream<List<AppUser>> allUsersStream() {
    return _db
        .collection(AppConstants.usersCollection)
        .snapshots()
        .map((snap) => snap.docs.map(AppUser.fromDoc).toList());
  }

  // ── Subjects ─────────────────────────────────────────────────────────────

  /// Streams subjects matching a course and semester.
  Stream<List<Subject>> subjectsStream({
    required String course,
    required int semester,
  }) {
    return _db
        .collection(AppConstants.subjectsCollection)
        .where('course', isEqualTo: course)
        .where('semester', isEqualTo: semester)
        .snapshots()
        .map((snap) => snap.docs.map(Subject.fromDoc).toList());
  }

  /// Gets all subjects (admin only).
  Stream<List<Subject>> allSubjectsStream() {
    return _db
        .collection(AppConstants.subjectsCollection)
        .snapshots()
        .map((snap) => snap.docs.map(Subject.fromDoc).toList());
  }

  /// Adds a subject.
  Future<void> addSubject(Subject subject) async {
    await _db
        .collection(AppConstants.subjectsCollection)
        .add(subject.toMap());
  }

  // ── Attendance ──────────────────────────────────────────────────────────

  /// Streams attendance records for a student.
  Stream<List<AttendanceRecord>> attendanceStream(String studentUid) {
    return _db
        .collection(AppConstants.attendanceCollection)
        .where('studentUid', isEqualTo: studentUid)
        .snapshots()
        .map((snap) => snap.docs.map(AttendanceRecord.fromDoc).toList());
  }

  /// Marks attendance for a student (admin/faculty only).
  /// Prevents duplicates by checking for an existing record with the same
  /// studentUid, subjectId, and classSessionId.
  Future<void> markAttendance({
    required String studentUid,
    required String subjectId,
    required String subjectName,
    required String classSessionId,
    required DateTime date,
    required String status,
  }) async {
    // Check for duplicate entry.
    final existing = await _db
        .collection(AppConstants.attendanceCollection)
        .where('studentUid', isEqualTo: studentUid)
        .where('subjectId', isEqualTo: subjectId)
        .where('classSessionId', isEqualTo: classSessionId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception(
        'Attendance already marked for this student, subject, and class session.',
      );
    }

    final markedBy = _auth.currentUser?.uid ?? '';
    await _db.collection(AppConstants.attendanceCollection).add({
      'studentUid': studentUid,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'classSessionId': classSessionId,
      'date': Timestamp.fromDate(date),
      'status': status,
      'markedBy': markedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Gets attendance for a student, optionally filtered by subject.
  Future<List<AttendanceRecord>> getAttendance(
    String studentUid, {
    String? subjectId,
  }) async {
    Query query = _db
        .collection(AppConstants.attendanceCollection)
        .where('studentUid', isEqualTo: studentUid);

    if (subjectId != null) {
      query = query.where('subjectId', isEqualTo: subjectId);
    }

    final snap = await query.get();
    return snap.docs.map(AttendanceRecord.fromDoc).toList();
  }

  // ── Timetable ─────────────────────────────────────────────────────────────

  /// Streams timetable entries for a course and semester.
  Stream<List<TimetableEntry>> timetableStream({
    required String course,
    required int semester,
  }) {
    return _db
        .collection(AppConstants.timetableCollection)
        .where('course', isEqualTo: course)
        .where('semester', isEqualTo: semester)
        .snapshots()
        .map((snap) => snap.docs.map(TimetableEntry.fromDoc).toList());
  }

  /// Adds a timetable entry.
  Future<void> addTimetableEntry(TimetableEntry entry) async {
    await _db
        .collection(AppConstants.timetableCollection)
        .add(entry.toMap());
  }

  /// Updates a timetable entry.
  Future<void> updateTimetableEntry(String id, TimetableEntry entry) async {
    await _db
        .collection(AppConstants.timetableCollection)
        .doc(id)
        .update(entry.toMap());
  }

  /// Deletes a timetable entry.
  Future<void> deleteTimetableEntry(String id) async {
    await _db.collection(AppConstants.timetableCollection).doc(id).delete();
  }

  // ── Assignments ──────────────────────────────────────────────────────────

  /// Streams assignments for a course and semester.
  Stream<List<Assignment>> assignmentsStream({
    required String course,
    required int semester,
  }) {
    return _db
        .collection(AppConstants.assignmentsCollection)
        .where('course', isEqualTo: course)
        .where('semester', isEqualTo: semester)
        .snapshots()
        .map((snap) => snap.docs.map(Assignment.fromDoc).toList());
  }

  /// Gets an assignment by ID.
  Future<Assignment?> getAssignment(String id) async {
    final doc =
        await _db.collection(AppConstants.assignmentsCollection).doc(id).get();
    if (!doc.exists) return null;
    return Assignment.fromDoc(doc);
  }

  /// Adds an assignment (admin/faculty only).
  Future<void> addAssignment(Assignment assignment) async {
    await _db.collection(AppConstants.assignmentsCollection).add({
      ...assignment.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates an assignment (admin/faculty only).
  Future<void> updateAssignment(String id, Assignment assignment) async {
    await _db.collection(AppConstants.assignmentsCollection).doc(id).update({
      ...assignment.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes an assignment (admin/faculty only).
  Future<void> deleteAssignment(String id) async {
    await _db.collection(AppConstants.assignmentsCollection).doc(id).delete();
  }

  // ── Assignment Submissions ───────────────────────────────────────────────

  /// Streams submissions for a specific assignment (admin/faculty view).
  Stream<List<AssignmentSubmission>> submissionsForAssignmentStream(
    String assignmentId,
  ) {
    return _db
        .collection(AppConstants.submissionsCollection)
        .where('assignmentId', isEqualTo: assignmentId)
        .snapshots()
        .map((snap) => snap.docs.map(AssignmentSubmission.fromDoc).toList());
  }

  /// Gets the current student's submission for an assignment.
  Future<AssignmentSubmission?> getMySubmission(
    String assignmentId,
    String studentUid,
  ) async {
    final snap = await _db
        .collection(AppConstants.submissionsCollection)
        .where('assignmentId', isEqualTo: assignmentId)
        .where('studentUid', isEqualTo: studentUid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AssignmentSubmission.fromDoc(snap.docs.first);
  }

  /// Submits or updates a student's assignment submission.
  Future<void> submitAssignment({
    required String assignmentId,
    required String studentUid,
    required String studentName,
    required String fileUrl,
    required bool isLate,
  }) async {
    // Check if a submission already exists for this student + assignment.
    final existing = await _db
        .collection(AppConstants.submissionsCollection)
        .where('assignmentId', isEqualTo: assignmentId)
        .where('studentUid', isEqualTo: studentUid)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      // Update existing submission.
      await _db
          .collection(AppConstants.submissionsCollection)
          .doc(existing.docs.first.id)
          .update({
        'fileUrl': fileUrl,
        'submittedAt': FieldValue.serverTimestamp(),
        'status': isLate ? 'late' : 'submitted',
      });
    } else {
      await _db.collection(AppConstants.submissionsCollection).add({
        'assignmentId': assignmentId,
        'studentUid': studentUid,
        'studentName': studentName,
        'fileUrl': fileUrl,
        'submittedAt': FieldValue.serverTimestamp(),
        'status': isLate ? 'late' : 'submitted',
        'feedback': null,
        'marks': null,
      });
    }
  }

  /// Updates a submission with feedback and marks (admin/faculty only).
  Future<void> gradeSubmission({
    required String submissionId,
    required String status,
    String? feedback,
    num? marks,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (feedback != null) updates['feedback'] = feedback;
    if (marks != null) updates['marks'] = marks;

    await _db
        .collection(AppConstants.submissionsCollection)
        .doc(submissionId)
        .update(updates);
  }

  // ── Notices ──────────────────────────────────────────────────────────────

  /// Streams published notices for students.
  Stream<List<Notice>> publishedNoticesStream() {
    return _db
        .collection(AppConstants.noticesCollection)
        .where('published', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Notice.fromDoc).toList());
  }

  /// Streams all notices (admin view).
  Stream<List<Notice>> allNoticesStream() {
    return _db
        .collection(AppConstants.noticesCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Notice.fromDoc).toList());
  }

  /// Adds a notice.
  Future<void> addNotice(Notice notice) async {
    await _db.collection(AppConstants.noticesCollection).add({
      ...notice.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Updates a notice.
  Future<void> updateNotice(String id, Notice notice) async {
    await _db.collection(AppConstants.noticesCollection).doc(id).update({
      ...notice.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a notice.
  Future<void> deleteNotice(String id) async {
    await _db.collection(AppConstants.noticesCollection).doc(id).delete();
  }

  /// Gets a single notice by ID.
  Future<Notice?> getNotice(String id) async {
    final doc =
        await _db.collection(AppConstants.noticesCollection).doc(id).get();
    if (!doc.exists) return null;
    return Notice.fromDoc(doc);
  }

  // ── Counts (for admin overview) ──────────────────────────────────────────

  /// Counts registered students.
  Future<int> countStudents() async {
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleStudent)
        .get();
    return snap.docs.length;
  }

  /// Counts all notices.
  Future<int> countNotices() async {
    final snap = await _db.collection(AppConstants.noticesCollection).get();
    return snap.docs.length;
  }

  /// Counts all assignments.
  Future<int> countAssignments() async {
    final snap =
        await _db.collection(AppConstants.assignmentsCollection).get();
    return snap.docs.length;
  }

  /// Counts all submissions.
  Future<int> countSubmissions() async {
    final snap =
        await _db.collection(AppConstants.submissionsCollection).get();
    return snap.docs.length;
  }
}
