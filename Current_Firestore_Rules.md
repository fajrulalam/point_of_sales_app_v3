rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // ── HELPER FUNCTIONS ──────────────────────────────────────────────────────

    function isAuthenticated() {
      return request.auth != null;
    }

    function isAdmin() {
      return isAuthenticated() && (
        request.auth.token.admin == true ||
        request.auth.token.email == "gnavsih1@gmail.com" ||
        request.auth.token.email == "admin@canteen375.com" ||
        request.auth.token.email == "irene@canteen375.com" ||
        request.auth.token.email == "amalia@canteen375.com" ||
        request.auth.token.email == "eka@canteen375.com" ||
        request.auth.token.email == "dina@canteen375.com"
      );
    }

    // Members doc id may be custom (fullName_phone); field uid == Firebase Auth UID.
    function isMemberProfileOwner() {
      return isAuthenticated() && resource.data.uid == request.auth.uid;
    }

    // userId / memberId on vouchers, feedbacks, orders may be Auth UID (legacy) or Members document id.
    function memberIdRefersToAuthUser(memberDocId) {
      return memberDocId == request.auth.uid ||
        (exists(/databases/$(database)/documents/Members/$(memberDocId)) &&
          get(/databases/$(database)/documents/Members/$(memberDocId)).data.uid == request.auth.uid);
    }

    // ── NEW COLLECTIONS FOR POS APP ───────────────────────────────────────────

    match /Categories/{id} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }

    match /assets/{id} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }

    match /config/{id} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }

    match /DailyTransaction/{id} {
      allow read, write: if isAuthenticated();
    }
    match /MonthlyTransaction/{id} {
      allow read, write: if isAuthenticated();
    }
    match /YearlyTransaction/{id} {
      allow read, write: if isAuthenticated();
    }
    match /DailyFinancialReport/{id} {
      allow read, write, update, delete: if true;

      match /Expenses/{expenseId} {
        allow read, write, update, delete: if true;
      }
    }
    match /Status/{id} { allow read, write, delete, update: if true; }
    match /Expenses/{id} { allow read, write: if isAuthenticated(); }
    match /CashflowSettings/{id} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }
    match /RecentlyServed/{id} { allow read, write, delete, update: if true; }

    // Maps Firebase Auth UID → Members document id (custom id).
    match /MemberLinks/{authUid} {
      allow read: if isAuthenticated() && request.auth.uid == authUid;
      allow create: if isAuthenticated()
                    && request.auth.uid == authUid
                    && request.resource.data.memberDocId is string
                    && request.resource.data.memberDocId.size() > 0;
      allow update, delete: if isAdmin();
    }

    // Members: document id is human-readable; field uid == Firebase Auth UID.
    // Register page checks duplicate via getDoc before sign-up (still anonymous): allow get only if doc is absent so existing profiles stay private.
    match /Members/{memberDocId} {
      allow get: if !exists(/databases/$(database)/documents/Members/$(memberDocId))
                  || isAuthenticated();
      allow list: if isAuthenticated();
      allow create: if isAuthenticated()
                    && request.resource.data.uid == request.auth.uid
                    && request.resource.data.role == "member";
      allow update: if isAdmin() || isMemberProfileOwner();
      allow delete: if isAdmin();
    }

    // ── VOUCHERS COLLECTIONS ──────────────────────────────────────────────────
    match /voucher/{id} {
      allow read: if isAdmin()
                    || (isAuthenticated() && memberIdRefersToAuthUser(resource.data.userId));
      allow write: if isAdmin();
    }
    match /vouchers/{id} {
      allow read: if isAdmin()
                    || (isAuthenticated() && memberIdRefersToAuthUser(resource.data.userId));
      // POS creates cashback vouchers on behalf of members during order processing.
      allow create: if isAuthenticated();
      allow update: if isAdmin()
                      || (isAuthenticated() && memberIdRefersToAuthUser(resource.data.userId));
      allow delete: if isAdmin();
    }

    // ── B2B VOUCHER PROGRAMS ─────────────────────────────────────────────────
    match /voucherPrograms/{id} {
      allow read: if isAuthenticated();
      // POS increments totalRedeemed atomically during order WriteBatch.
      // Settlement (settleProgram) updates totalSettled and status from POS.
      allow update: if isAuthenticated();
      allow create, delete: if isAdmin();
    }

    // ── VOUCHER GROUP (CAMPAIGNS) ─────────────────────────────────────────────
    match /voucherGroup/{groupId} {
      allow read: if isAuthenticated();
      allow create, delete: if isAdmin();
      // POS increments totalParticipants on cashback campaigns during order processing.
      allow update: if isAuthenticated();
    }

    // ── COMPETITION RECORDS (LEADERBOARD DATA) ────────────────────────────────
    match /competitionRecords/{monthId} {
      allow read: if isAuthenticated();
      // POS writes member scores (customerPoints, amountSpent, numberOfTransaction) during order processing.
      allow write: if isAuthenticated();
    }

    // ── FEEDBACKS ─────────────────────────────────────────────────────────────
    match /feedbacks/{feedbackId} {
      allow create: if isAuthenticated()
                    && memberIdRefersToAuthUser(request.resource.data.memberId);
      allow read: if isAdmin()
                    || (isAuthenticated() && memberIdRefersToAuthUser(resource.data.memberId));
      allow update, delete: if isAdmin();
    }

    // ── CANTEENS (BRANCH DATA) ────────────────────────────────────────────────
    match /Canteens/{canteenId} {

      allow read: if isAuthenticated();
      allow update: if isAuthenticated();
      allow create, delete: if isAdmin();

      match /Inventory/{id} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }

      match /DailyStockLogs/{id} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }

      match /MenuCollection/{menuId} {
        allow read: if true;
        allow write: if isAdmin();
      }

      match /Metadata/{configId} {
        allow read: if isAuthenticated();
        allow write: if isAdmin() || (isAuthenticated() && configId == 'SelfOrderCounter');
      }

      match /Metadata/Settings {
        allow read: if isAuthenticated();
      }

      match /OptionGroups/{groupId} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }

      match /suppliers/{supplierId} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }

      match /shoppingOrders/{orderId} {
        allow read: if isAuthenticated();
        allow write: if isAdmin();
      }

      match /Status/{orderId} {
        allow read, write, update, delete: if true;
      }

      match /RecentlyServed/{orderId} {
        allow read, write, update, delete: if true;
      }

      match /SelfOrders/{orderId} {
        allow read: if isAdmin()
                      || (isAuthenticated() && memberIdRefersToAuthUser(resource.data.memberId));
        allow create: if isAuthenticated()
                        && memberIdRefersToAuthUser(request.resource.data.memberId);
        allow update, delete: if isAdmin();
      }

      match /OpenBills/{memberId} {
        allow read, write, update, delete: if isAuthenticated();

        match /Orders/{tabOrderId} {
          allow read, write, update, delete: if isAuthenticated();
        }
      }

      match /SettledBills/{billId} {
        allow read, write, update, delete: if isAuthenticated();
      }

      match /Orders/{orderID} {
        allow read, write, update, delete: if isAuthenticated();
      }
    }

    // ── PUBLIC PRODUCTS (OLD VERSION) ─────────────────────────────────────────
    match /products/{productId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    match /products_test/{productId} {
      allow read: if true;
      allow write: if isAdmin();
    }

    // ── TESTING MODE COLLECTIONS (zTesting_ prefix) ──────────────────────────────
    match /zTesting_Categories/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_DailyTransaction/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_MonthlyTransaction/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_YearlyTransaction/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_DailyFinancialReport/{id} {
      allow read, write, update, delete: if true;
      match /Expenses/{expenseId} {
        allow read, write, update, delete: if true;
      }
    }

    match /zTesting_Expenses/{id} {
      allow read, write: if true;
    }

    match /zTesting_Status/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_RecentlyServed/{id} {
      allow read, write, delete, update: if true;
    }

    match /zTesting_Members/{uid} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_CashflowSettings/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_competitionRecords/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_voucher/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_vouchers/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_voucherGroup/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_voucherPrograms/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_MemberLinks/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_Canteens/{canteenId} {
      allow read, write, update, delete: if true;

      match /{subcollection=**} {
        allow read, write, update, delete: if true;
      }
    }
  }
}
