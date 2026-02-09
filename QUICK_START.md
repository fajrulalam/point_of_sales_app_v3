# 🚀 Quick Start - Recommendation System

## ⚡ 3-Step Setup

### 1️⃣ Install Dependencies

```bash
flutter pub get
```

### 2️⃣ Firebase Storage Setup

- Go to: https://console.firebase.google.com
- Navigate to: **Storage** → Create folder `recommendation_rules`
- Upload your `rules_final.csv` to: `recommendation_rules/rules_final.csv`

### 3️⃣ Firestore Configuration

- Go to: **Firestore Database**
- Create collection: `config`
- Create document: `recommendations` with these fields:

```
version: "2025-11-03-v1" (string)
csvFileName: "rules_final.csv" (string)
matchThreshold: 1.0 (number)
minConfidence: 0.5 (number)
maxRecommendations: 5 (number)
enabled: true (boolean)
```

---

## ✅ Test It

1. Run: `flutter run`
2. Add items to cart (e.g., "ayam goreng", "nasi putih")
3. Click **BELI**
4. Check console logs for recommendations!

---

## 🔧 Quick Config Changes

### Enable/Disable System

```
Firestore → config → recommendations → enabled: false
```

### Change Match Strictness

```
matchThreshold: 1.0  → All antecedents must match (strict)
matchThreshold: 0.5  → Half of antecedents must match (lenient)
```

### Show More/Less Recommendations

```
maxRecommendations: 3  → Show top 3
maxRecommendations: 10 → Show top 10
```

---

## 🔄 Update Rules (Future)

1. Generate new CSV
2. Upload to Firebase Storage (overwrite)
3. Update Firestore: `version: "2025-11-10-v2"`
4. App auto-updates on next restart!

---

## 📖 Full Documentation

See: `RECOMMENDATION_SYSTEM_SETUP.md` for complete details

---

**That's it! 🎉**
