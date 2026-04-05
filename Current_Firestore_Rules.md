rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // ── HELPER FUNCTIONS ──────────────────────────────────────────────────────
    
    function isAuthenticated() {
      return request.auth != null;
    }

    function isAdmin() {
      // UPDATED: Now recognizes your specific email as an Admin
      return isAuthenticated() && (
        request.auth.token.admin == true || 
        request.auth.token.email == "gnavsih1@gmail.com" || 
        request.auth.token.email == "admin@canteen375.com"
      );
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
      allow read: if true;
      allow write: if isAdmin();
    }
    match /MonthlyTransaction/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }
    match /YearlyTransaction/{id} {
      allow read: if true;
      allow write: if isAdmin();
    }
    match /DailyFinancialReport/{id} {
      allow read, write, update, delete: if true;

      match /Expenses/{expenseId} {
        allow read, write, update, delete: if true;
      }
    }
    match /Status/{id} { allow read, write, delete, update: if true; }
    match /Expenses/{id} { allow read, write: if isAuthenticated(); }
    match /RecentlyServed/{id} { allow read, write, delete, update: if true; }


    // ── MEMBERS COLLECTION ─────────────────────────────────────────────────────
    match /Members/{uid} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() 
                    && request.auth.uid == uid 
                    && request.resource.data.uid == uid;
      allow update: if isAdmin() || (isAuthenticated() && request.auth.uid == uid);
      allow delete: if isAdmin();
    }

    // ── VOUCHERS COLLECTIONS ──────────────────────────────────────────────────
    match /voucher/{id} {
      allow read: if isAdmin() || (isAuthenticated() && resource.data.userId == request.auth.uid);
      allow write: if isAdmin();
    }
    match /vouchers/{id} {
      allow read: if isAdmin() || (isAuthenticated() && resource.data.userId == request.auth.uid);
      allow write: if isAdmin();
    }

    // ── VOUCHER GROUP (CAMPAIGNS) ─────────────────────────────────────────────
    match /voucherGroup/{groupId} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }

    // ── COMPETITION RECORDS (LEADERBOARD DATA) ────────────────────────────────
    match /competitionRecords/{monthId} {
      allow read: if isAuthenticated();
      allow write: if isAdmin();
    }

    // ── FEEDBACKS ─────────────────────────────────────────────────────────────
    match /feedbacks/{feedbackId} {
      allow create: if isAuthenticated() && request.resource.data.memberId == request.auth.uid;
      allow read: if isAdmin() || (isAuthenticated() && resource.data.memberId == request.auth.uid);
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
        allow read: if isAuthenticated();
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
      
      // STATUS & RECENTLY SERVED: Order queue and completed orders
      match /Status/{orderId} {
        allow read, write, update, delete: if true;
      }
      
      match /RecentlyServed/{orderId} {
        allow read, write, update, delete: if true;
      }
      
      match /SelfOrders/{orderId} {
        allow read: if isAdmin() || (isAuthenticated() && resource.data.memberId == request.auth.uid);
        allow create: if isAuthenticated() && request.resource.data.memberId == request.auth.uid;
        // Only admins/POS can update status.
        allow update, delete: if isAdmin();
      }
      
      match /OpenBills/{memberId} {
        // Broad access for all authenticated POS users to read and write to standard bills
        allow read, write, update, delete: if isAuthenticated();
        
        // Explicitly allow writing to the nested subcollection where individual tab entries live
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

    match /zTesting_Canteens/{canteenId} {
      allow read, write, update, delete: if true;

      match /{subcollection=**} {
        allow read, write, update, delete: if true;
      }
    }

    match /zTesting_competitionRecords/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_vouchers/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_voucher/{id} {
      allow read, write, update, delete: if true;
    }

    match /zTesting_voucherGroup/{id} {
      allow read, write, update, delete: if true;
    }
  }
}