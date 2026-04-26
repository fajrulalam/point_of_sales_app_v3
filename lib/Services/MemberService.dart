import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Services/DatabaseHelper.dart';

class MemberService {
  static final MemberService instance = MemberService._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Prevents overlapping background syncs when checkout opens repeatedly.
  bool _backgroundRefreshRunning = false;

  MemberService._init();

  // Initialization: Fetch and cache all members
  Future<void> initializeCache() async {
    try {
      // Wait for authentication if not ready
      int authAttempts = 0;
      while (FirebaseAuth.instance.currentUser == null && authAttempts < 5) {
        await Future.delayed(const Duration(milliseconds: 1000));
        authAttempts++;
      }

      print('🔄 Initializing Members cache...');
      await fetchAndCacheMembers();
      print('✅ Members cache initialized.');
    } catch (e) {
      print('❌ Error initializing members cache: $e');
    }
  }

  // Fetch all members from Firestore and update local cache
  Future<void> fetchAndCacheMembers() async {
    try {
      final snapshot = await _firestore.collection(Col.name('Members')).get();
      final members = snapshot.docs
          .map((doc) => Member.fromFirestore(doc.id, doc.data()))
          .toList();

      if (members.isNotEmpty) {
        // Clear old cache and insert new data
        await _dbHelper.clearMembers();
        await _dbHelper.insertMembers(members);
        
        // Update metadata for last sync time
        await _dbHelper.setMetadata('members_last_sync', DateTime.now().toIso8601String());
        print('📦 Cached ${members.length} members.');
      }
    } catch (e) {
      print('❌ Error fetching members from Firestore: $e');
      rethrow;
    }
  }

  // Get members from local cache
  Future<List<Member>> getCachedMembers() async {
    return await _dbHelper.getAllMembers();
  }

  // Search members in local cache
  Future<List<Member>> searchCachedMembers(String query) async {
    if (query.isEmpty) return getCachedMembers();
    return await _dbHelper.searchMembers(query);
  }

  // Update a single member in cache (used when adding a member)
  Future<void> updateSingleMemberCache(Member member) async {
    await _dbHelper.insertMember(member);
    print('👤 Updated cache for member: ${member.name}');
  }

  // Force sync (manually triggered)
  Future<void> forceSync() async {
    await fetchAndCacheMembers();
  }

  /// Refreshes the local member cache from Firestore **without blocking** the caller.
  /// Runs only if [members_last_sync] is missing or older than [minInterval].
  /// Safe to call when opening order confirmation; overlaps with user filling the form.
  void scheduleMembersCacheRefreshIfStale({
    Duration minInterval = const Duration(minutes: 3),
  }) {
    _scheduleMembersCacheRefreshIfStaleImpl(minInterval);
  }

  Future<void> _scheduleMembersCacheRefreshIfStaleImpl(
    Duration minInterval,
  ) async {
    if (_backgroundRefreshRunning) return;
    _backgroundRefreshRunning = true;
    try {
      final lastStr = await _dbHelper.getMetadata('members_last_sync');
      if (lastStr != null) {
        final last = DateTime.tryParse(lastStr);
        if (last != null &&
            DateTime.now().difference(last) < minInterval) {
          return;
        }
      }
      await fetchAndCacheMembers();
    } catch (e) {
      print('⚠️ Background members refresh failed: $e');
    } finally {
      _backgroundRefreshRunning = false;
    }
  }
}
