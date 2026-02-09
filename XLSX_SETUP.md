# 📊 XLSX Setup Guide - Updated!

## ✅ XLSX Support Added!

Your recommendation system now supports **XLSX (Excel)** files in addition to CSV. This is more robust as it uses **column names** instead of column positions.

---

## 🎯 Required Columns in XLSX

Your Excel file MUST have these column headers (case-insensitive):

| Column Name   | Required | Format              | Example                      |
| ------------- | -------- | ------------------- | ---------------------------- |
| `antecedents` | ✅ Yes   | frozenset string    | `frozenset({'ayam goreng'})` |
| `consequents` | ✅ Yes   | frozenset string    | `frozenset({'nasi putih'})`  |
| `confidence`  | ✅ Yes   | Number (0.0 to 1.0) | `0.5609` (56.09%)            |
| `support`     | ❌ No    | Optional            | Any value (ignored)          |
| `lift`        | ❌ No    | Optional            | Any value (ignored)          |

**Note:** Only `antecedents`, `consequents`, and `confidence` are used. All other columns are ignored.

---

## 📋 Your Action Items

### 1️⃣ Install New Dependency

```bash
cd /Users/fajmac/StudioProjects/point_of_sales_app_v3
flutter pub get
```

### 2️⃣ Update Firestore Configuration

Go to **Firestore** → `config` → `recommendations` document:

**Change this field:**

```
csvFileName: "rules_final.xlsx"  ← Change from .csv to .xlsx
```

**Also update version to force re-download:**

```
version: "2025-11-03-v2"  ← Change version number
```

### 3️⃣ Upload XLSX to Firebase Storage

1. Go to Firebase Storage
2. Navigate to `recommendation_rules/` folder
3. **Delete** the old `rules_final.csv` (optional)
4. **Upload** your `rules_final.xlsx` file
5. Verify path is: `recommendation_rules/rules_final.xlsx`

### 4️⃣ Verify Excel Format

Make sure your XLSX has:

- ✅ First row is header with column names: `antecedents`, `consequents`, `confidence`
- ✅ Data starts from row 2
- ✅ Antecedents and consequents are in frozenset format: `frozenset({'item name'})`
- ✅ Confidence is a decimal number (0.5 = 50%)

**Example rows:**

| antecedents                | consequents               | confidence | support | lift  |
| -------------------------- | ------------------------- | ---------- | ------- | ----- |
| frozenset({'ayam goreng'}) | frozenset({'nasi putih'}) | 0.5609     | 0.00268 | 14.32 |
| frozenset({'nasi putih'})  | frozenset({'mie'})        | 0.6428     | 0.02518 | 3.276 |

---

## 🚀 Test It!

```bash
flutter run
```

**Expected console output:**

```
🔄 Initializing recommendation system...
📥 Re-downloading rules (database is empty)...
✅ File downloaded successfully (XLSX)
📊 Reading XLSX file...
📊 Found sheet: Sheet1 with 125 rows
🔍 Column indices - Antecedents: 1, Consequents: 2, Confidence: 6
🔍 ===== FIRST 5 ROWS FROM XLSX =====
Row 1: Antecedents=frozenset({'ayam goreng'}), Consequents=frozenset({'nasi putih'}), Confidence=0.5609
Row 2: Antecedents=frozenset({'nasi putih'}), Consequents=frozenset({'mie'}), Confidence=0.6428
...
✅ Parsed 124 rules from XLSX
✅ Recommendation system initialized with 124 rules
```

---

## 🔧 Benefits of XLSX

✅ **Column order doesn't matter** - Uses column names  
✅ **More robust** - Excel files are easier to edit  
✅ **Visual editing** - Can edit in Excel/Google Sheets  
✅ **Better debugging** - Can see data structure clearly  
✅ **Flexible** - Can have extra columns (they're ignored)

---

## 🐛 Troubleshooting

### Problem: "Required columns not found"

**Check:**

- Column headers are exactly: `antecedents`, `consequents`, `confidence` (case-insensitive)
- No extra spaces in column names
- Headers are in the first row

### Problem: "0 rules parsed"

**Check:**

- Data starts from row 2 (row 1 is headers)
- Antecedents/consequents are in frozenset format
- Cells are not empty
- File is actually `.xlsx` format (not `.xls` or CSV renamed)

### Problem: File download fails

**Check:**

- Firestore config has correct filename: `rules_final.xlsx`
- Firebase Storage path is: `recommendation_rules/rules_final.xlsx`
- Version was updated in Firestore config

---

## 📊 CSV Still Supported!

The system auto-detects file type:

- Files ending in `.xlsx` or `.xls` → parsed as Excel
- Files ending in `.csv` → parsed as CSV

You can switch between formats anytime by:

1. Uploading new file to Storage
2. Updating `csvFileName` in Firestore config
3. Updating `version` to force re-download

---

## 🎉 You're All Set!

Run the app and check the console logs. If you see rules being parsed successfully, you're good to go! 🚀

**Still having issues?** Share the console output and I'll help debug!
