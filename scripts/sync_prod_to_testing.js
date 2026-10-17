#!/usr/bin/env node
/**
 * Syncs menu, stock/inventory, option groups, and menu-stock relationships
 * from Production mode to Testing mode in Firebase Firestore.
 *
 * Usage:
 *   node scripts/sync_prod_to_testing.js          # Dry run: previews changes
 *   node scripts/sync_prod_to_testing.js --apply  # Applies sync to Firestore
 */

const path = require('path');
const { createRequire } = require('module');

const ROOT = path.join(__dirname, '..');
const requireFromFunctions = createRequire(path.join(ROOT, 'functions', 'package.json'));
const { initializeApp, cert } = requireFromFunctions('firebase-admin/app');
const { getFirestore } = requireFromFunctions('firebase-admin/firestore');

const KEY_PATH = path.join(ROOT, 'point-of-sales-app-25e2b-firebase-adminsdk-isjye-3ddd9cdd88.json');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');

initializeApp({
  credential: cert(KEY_PATH),
});

const db = getFirestore();
const CANTEEN_ID = 'canteen375';

// Chunk helper for batch operations (max 400 to stay safely under 500 limit)
function chunkList(arr, size = 400) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

async function syncSubcollection(sourceColRef, targetColRef, name) {
  console.log(`\n========================================`);
  console.log(`Syncing ${name}...`);
  console.log(`========================================`);

  const [srcSnap, targetSnap] = await Promise.all([
    sourceColRef.get(),
    targetColRef.get(),
  ]);

  console.log(`Production documents: ${srcSnap.size}`);
  console.log(`Testing documents (current): ${targetSnap.size}`);

  const srcDocs = srcSnap.docs;
  const targetDocs = targetSnap.docs;

  const srcIds = new Set(srcDocs.map(d => d.id));
  const targetIds = new Set(targetDocs.map(d => d.id));

  const toDelete = targetDocs.filter(d => !srcIds.has(d.id));
  const toUpdate = srcDocs.filter(d => targetIds.has(d.id));
  const toCreate = srcDocs.filter(d => !targetIds.has(d.id));

  console.log(`  - To create: ${toCreate.length}`);
  console.log(`  - To update: ${toUpdate.length}`);
  console.log(`  - To delete (orphans in test): ${toDelete.length}`);

  if (toDelete.length > 0) {
    console.log(`    Orphan IDs to delete:`, toDelete.map(d => d.id));
  }

  if (!APPLY) {
    console.log(`  [DRY-RUN] No writes performed.`);
    return;
  }

  // Delete orphaned documents
  if (toDelete.length > 0) {
    for (const chunk of chunkList(toDelete)) {
      const batch = db.batch();
      for (const doc of chunk) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
    console.log(`  ✅ Deleted ${toDelete.length} orphaned test documents.`);
  }

  // Copy/overwrite all production documents
  for (const chunk of chunkList(srcDocs)) {
    const batch = db.batch();
    for (const doc of chunk) {
      batch.set(targetColRef.doc(doc.id), doc.data());
    }
    await batch.commit();
  }
  console.log(`  ✅ Written ${srcDocs.length} production documents to testing mode.`);
}

async function syncDoc(sourceDocRef, targetDocRef, name) {
  console.log(`\nSyncing document ${name}...`);
  const srcDoc = await sourceDocRef.get();
  if (!srcDoc.exists) {
    console.log(`  ⚠️ Source doc ${name} does not exist!`);
    return;
  }

  console.log(`  Source doc ${name} exists. Fields:`, Object.keys(srcDoc.data()));

  if (!APPLY) {
    console.log(`  [DRY-RUN] No writes performed.`);
    return;
  }

  await targetDocRef.set(srcDoc.data());
  console.log(`  ✅ Successfully updated ${name} in testing mode.`);
}

async function verifyTestingIntegrity() {
  console.log(`\n========================================`);
  console.log(`Verifying Testing Data Integrity...`);
  console.log(`========================================`);

  const tCanteen = db.collection('zTesting_Canteens').doc(CANTEEN_ID);

  const [menuSnap, invSnap, optSnap, stockSnap] = await Promise.all([
    tCanteen.collection('MenuCollection').get(),
    tCanteen.collection('Inventory').get(),
    tCanteen.collection('OptionGroups').get(),
    tCanteen.collection('StockCollection').get(),
  ]);

  console.log(`Testing collection sizes:`);
  console.log(`  MenuCollection:  ${menuSnap.size}`);
  console.log(`  Inventory:       ${invSnap.size}`);
  console.log(`  OptionGroups:    ${optSnap.size}`);
  console.log(`  StockCollection: ${stockSnap.size}`);

  const invIds = new Set(invSnap.docs.map(d => d.id));
  const invNames = new Set(invSnap.docs.map(d => (d.data().name || '').trim().toLowerCase()));

  // Verify Menu ingredients
  let menuUnresolved = 0;
  menuSnap.docs.forEach(doc => {
    const data = doc.data();
    (data.ingredients || []).forEach(ing => {
      const id = (ing.inventoryItemId || '').trim();
      const name = (ing.inventoryItemName || '').trim().toLowerCase();
      if (!invIds.has(id) && !invNames.has(name)) {
        console.warn(`  ⚠️ Menu "${data.namaMenu}" (${doc.id}) references missing inventory item: id="${id}", name="${ing.inventoryItemName}"`);
        menuUnresolved++;
      }
    });
  });

  // Verify Option ingredients
  let optUnresolved = 0;
  optSnap.docs.forEach(doc => {
    const data = doc.data();
    (data.options || []).forEach(opt => {
      (opt.ingredients || []).forEach(ing => {
        const id = (ing.inventoryItemId || '').trim();
        const name = (ing.inventoryItemName || '').trim().toLowerCase();
        if (!invIds.has(id) && !invNames.has(name)) {
          console.warn(`  ⚠️ Option "${opt.name}" in Group "${data.name}" references missing inventory item: id="${id}", name="${ing.inventoryItemName}"`);
          optUnresolved++;
        }
      });
    });
  });

  if (menuUnresolved === 0 && optUnresolved === 0) {
    console.log(`  ✅ All menu & option ingredient references successfully resolve to items in Inventory!`);
  } else {
    console.warn(`  ❌ Found ${menuUnresolved + optUnresolved} unresolved references!`);
  }
}

async function main() {
  console.log(`MODE: ${APPLY ? '🚀 APPLY (Live Writes)' : '🔍 DRY-RUN (Read-Only Preview)'}`);
  console.log(`Canteen: ${CANTEEN_ID}`);

  const pCanteen = db.collection('Canteens').doc(CANTEEN_ID);
  const tCanteen = db.collection('zTesting_Canteens').doc(CANTEEN_ID);

  // 1. Ensure testing canteen document exists
  const pCanteenDoc = await pCanteen.get();
  if (APPLY) {
    await tCanteen.set(pCanteenDoc.data() || {}, { merge: true });
  }

  // 2. Sync MenuCollection
  await syncSubcollection(
    pCanteen.collection('MenuCollection'),
    tCanteen.collection('MenuCollection'),
    'MenuCollection'
  );

  // 3. Sync Inventory (Stock)
  await syncSubcollection(
    pCanteen.collection('Inventory'),
    tCanteen.collection('Inventory'),
    'Inventory'
  );

  // 4. Sync OptionGroups
  await syncSubcollection(
    pCanteen.collection('OptionGroups'),
    tCanteen.collection('OptionGroups'),
    'OptionGroups'
  );

  // 5. Sync StockCollection
  await syncSubcollection(
    pCanteen.collection('StockCollection'),
    tCanteen.collection('StockCollection'),
    'StockCollection'
  );

  // 6. Sync Metadata/MenuConfig
  await syncDoc(
    pCanteen.collection('Metadata').doc('MenuConfig'),
    tCanteen.collection('Metadata').doc('MenuConfig'),
    'Metadata/MenuConfig'
  );

  // 7. Sync Metadata/InventoryLogs
  await syncDoc(
    pCanteen.collection('Metadata').doc('InventoryLogs'),
    tCanteen.collection('Metadata').doc('InventoryLogs'),
    'Metadata/InventoryLogs'
  );

  // 8. If applied, verify data integrity
  if (APPLY) {
    await verifyTestingIntegrity();
  } else {
    console.log(`\nRun with --apply to execute these changes:`);
    console.log(`  node scripts/sync_prod_to_testing.js --apply\n`);
  }
}

main().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
