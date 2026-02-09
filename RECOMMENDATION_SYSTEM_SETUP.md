# 🎯 Recommendation System Setup Guide

## Overview

Your recommendation system is now implemented using **Option 1** (Firebase Storage + SQLite). This guide will walk you through the setup steps.

---

## ✅ What's Already Done

I've implemented:

1. ✅ **RecommendationModels.dart** - Data models for rules and recommendations
2. ✅ **DatabaseHelper.dart** - SQLite database management
3. ✅ **RecommendationService.dart** - Main recommendation logic
4. ✅ **OrderConfirmationService.dart** - Integrated with BELI button
5. ✅ **main.dart** - Auto-initialization on app startup
6. ✅ **pubspec.yaml** - Added required dependencies

---

## 🚀 YOUR ACTION ITEMS

### Step 1: Install New Dependencies

Run this command in your terminal:

```bash
cd /Users/fajmac/StudioProjects/point_of_sales_app_v3
flutter pub get
```

---

### Step 2: Upload CSV to Firebase Storage

1. Open **Firebase Console**: https://console.firebase.google.com
2. Select your project
3. Go to **Storage** in the left menu
4. Create a folder called `recommendation_rules`
5. Upload your `rules_final.csv` file to this folder

**Final path should be**: `recommendation_rules/rules_final.csv`

**Security Rules** (if needed):

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /recommendation_rules/{allPaths=**} {
      allow read: if request.auth != null;  // Authenticated users can read
      allow write: if false;  // Only admins via console
    }
  }
}
```

---

### Step 3: Create Configuration in Firestore

1. Open **Firebase Console** → **Firestore Database**
2. Create a new collection called `config`
3. Add a document with ID: `recommendations`
4. Add these fields:

| Field                | Type      | Value               | Description                       |
| -------------------- | --------- | ------------------- | --------------------------------- |
| `version`            | string    | `2025-11-03-v1`     | Version identifier for rules      |
| `csvFileName`        | string    | `rules_final.csv`   | Name of CSV file in Storage       |
| `matchThreshold`     | number    | `1.0`               | 1.0 = 100% antecedents must match |
| `minConfidence`      | number    | `0.5`               | Minimum confidence (0.5 = 50%)    |
| `maxRecommendations` | number    | `5`                 | Maximum recommendations to show   |
| `enabled`            | boolean   | `true`              | Enable/disable system             |
| `lastUpdated`        | timestamp | (Current timestamp) | When rules were last updated      |

**Example JSON** (if you prefer to import):

```json
{
  "version": "2025-11-03-v1",
  "csvFileName": "rules_final.csv",
  "matchThreshold": 1.0,
  "minConfidence": 0.5,
  "maxRecommendations": 5,
  "enabled": true,
  "lastUpdated": "2025-11-03T00:00:00.000Z"
}
```

---

### Step 4: Run the App

```bash
flutter run
```

**What happens on startup:**

1. App initializes Firebase
2. Recommendation system loads configuration from Firestore
3. If CSV version is new, downloads and parses rules
4. Stores rules in local SQLite database
5. System is ready!

---

## 🧪 Testing

### Test 1: Check Console Logs

When app starts, you should see:

```
🔄 Initializing recommendation system...
📥 Downloading new rules (version: 2025-11-03-v1)...
✅ CSV downloaded successfully
✅ Parsed XXX rules from CSV
✅ Rules database updated successfully
✅ Recommendation system initialized with XXX rules
```

### Test 2: Make an Order

1. Add items to cart (e.g., "ayam goreng", "nasi putih")
2. Click **BELI** button
3. Check console logs for recommendations:

```
🛒 Current order items: ayam goreng, nasi putih
✨ ====== RECOMMENDATIONS ======
📊 Found 3 recommendations:

1. mie (64.3% confidence)
   Based on: nasi putih

2. teh (81.9% confidence)
   Based on: nasi putih

3. gorengan (73.5% confidence)
   Based on: nasi putih, ayam goreng

================================
```

---

## 🔧 Configuration Options

### Adjusting Match Threshold

In Firestore config document:

- **`matchThreshold: 1.0`** (100%) - ALL antecedents must be in order
  - Example: Rule `{ayam, nasi}` → needs BOTH ayam AND nasi
- **`matchThreshold: 0.5`** (50%) - At least HALF of antecedents

  - Example: Rule `{ayam, nasi}` → needs EITHER ayam OR nasi

- **`matchThreshold: 0.66`** (66%) - At least TWO-THIRDS
  - Example: Rule `{ayam, nasi, teh}` → needs ANY 2 of 3

**Recommended**: Start with `1.0` for strict matching

### Adjusting Confidence Threshold

- **`minConfidence: 0.5`** - Only show recommendations with 50%+ confidence
- **`minConfidence: 0.7`** - Only show high-confidence recommendations (70%+)
- **`minConfidence: 0.3`** - Show more recommendations (30%+)

---

## 🔄 Updating Rules (Future)

When you have new association rules:

### Option A: Same CSV Name (Easiest)

1. Generate new `rules_final.csv` from your data
2. Upload to Firebase Storage (overwrite old file)
3. In Firestore config, update `version` field: `2025-11-10-v2`
4. Next app restart will auto-download new rules!

### Option B: Different CSV Name

1. Upload new CSV: `rules_november_2025.csv`
2. Update Firestore config:
   - `csvFileName`: `rules_november_2025.csv`
   - `version`: `2025-11-10-v2`
3. Next app restart will auto-download

### Force Manual Refresh (Without Restart)

Add this code where needed:

```dart
await RecommendationService.instance.forceRefresh();
```

---

## 📊 Viewing Statistics

Add this code to see system statistics:

```dart
final stats = await RecommendationService.instance.getStatistics();
print('📈 Statistics: $stats');
```

Output:

```dart
{
  'ruleCount': 124,
  'version': '2025-11-03-v1',
  'lastUpdated': '2025-11-03T10:30:00.000Z',
  'enabled': true,
  'initialized': true
}
```

---

## 🐛 Troubleshooting

### Problem: No recommendations showing

**Check:**

1. ✅ Is `enabled: true` in Firestore config?
2. ✅ Does console show initialization messages?
3. ✅ Are you testing with items that exist in the CSV?
4. ✅ Is `matchThreshold` too high? Try `0.5`

### Problem: CSV download fails

**Check:**

1. ✅ Firebase Storage rules allow authenticated reads
2. ✅ CSV file path is exactly `recommendation_rules/rules_final.csv`
3. ✅ App is signed in (if auth required)

### Problem: Rules not updating

**Check:**

1. ✅ Did you change the `version` field in Firestore?
2. ✅ Try uninstalling and reinstalling the app
3. ✅ Or call `forceRefresh()` programmatically

---

## 📝 CSV Format Requirements

Your CSV must have these columns (in order):

1. Column 1: Index (ignored)
2. **Column 2: Antecedents** - Format: `frozenset({'item1', 'item2'})`
3. **Column 3: Consequents** - Format: `frozenset({'item3'})`
4. Column 4: Support
5. Column 5-6: (ignored)
6. **Column 7: Confidence**
7. **Column 8: Lift**

**Example Row:**

```csv
0,frozenset({'ayam goreng'}),frozenset({'nasi putih'}),0.0026,0.0047,0.0001,0.5609,14.31
```

**Important:**

- Item names must match exactly with menu items (case-insensitive)
- Use lowercase in CSV for better matching
- Special characters are OK

---

## 🎨 Next Steps (Future UI)

Once recommendations are working, you can:

1. **Show recommendations in dialog** when BELI is clicked
2. **Add quick-add buttons** for recommended items
3. **Track acceptance rate** (which recommendations users actually add)
4. **A/B test different thresholds** to optimize
5. **Show "Customers also bought" section** in UI

---

## 📞 Support

If you encounter issues:

1. Check console logs for error messages
2. Verify Firebase Storage and Firestore setup
3. Test with a simple order first (e.g., just "ayam goreng")
4. Check that item names in orders match CSV exactly

---

## 🎉 Success Criteria

You'll know it's working when:

- ✅ App starts without errors
- ✅ Console shows "Recommendation system initialized"
- ✅ Clicking BELI shows recommendations in console
- ✅ Recommendations make sense based on your rules

**Ready to test? Follow the steps above and let me know if you hit any issues!**
