#!/usr/bin/env node
// Creates the end-of-day financial report (DailyFinancialReport) for a day the cashier forgot to close,
// exactly as FinancialReportBottomSheet._submitReport would have, from the counted amounts.
//
//   node scripts/backfill_daily_closing.js --date 2026-10-16 --cash 1155000 --qris 927000            # dry run
//   node scripts/backfill_daily_closing.js --date 2026-10-16 --cash 1155000 --qris 927000 --apply    # writes
//
// --online is optional and defaults to that day's online sales (nothing to count by hand for online).
// Refuses if that day already has a closing, or if a later day was already closed.

const path = require('path');
const { createRequire } = require('module');

const ROOT = path.join(__dirname, '..');
const requireFromFunctions = createRequire(path.join(ROOT, 'functions', 'package.json'));
const { initializeApp, cert } = requireFromFunctions('firebase-admin/app');
const { getFirestore, FieldValue, FieldPath, Timestamp } = requireFromFunctions('firebase-admin/firestore');

const KEY_PATH = path.join(ROOT, 'point-of-sales-app-25e2b-firebase-adminsdk-isjye-3ddd9cdd88.json');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const flag = (name) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? undefined : args[i + 1];
};

const rp = (n) => `Rp ${Number(n || 0).toLocaleString('id-ID')}`;
const toInt = (v) => (typeof v === 'number' ? Math.trunc(v) : parseInt(v, 10) || 0);
const wibDate = (d) => new Date(d.getTime() + 7 * 3600e3).toISOString().slice(0, 10);
const ACCOUNTS = [
  ['Cash', 'Cash'],
  ['Qris', 'QRIS'],
  ['Online', 'Online'],
]; // [field suffix, Expenses.sourceAccount]

function readInput() {
  const date = flag('date');
  const errors = [];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '') || wibDate(new Date(`${date}T00:00:00+07:00`)) !== date) {
    errors.push('--date must be a real day written as YYYY-MM-DD');
  } else if (date >= wibDate(new Date())) {
    errors.push('--date must be before today (WIB); closing today is done in the app');
  }
  const amount = (name, optional) => {
    const raw = flag(name);
    if (raw === undefined && optional) return undefined;
    if (!/^\d+$/.test(raw || '')) errors.push(`--${name} must be a whole number of rupiah, 0 or more`);
    return Number(raw);
  };
  const input = { date, cash: amount('cash'), qris: amount('qris'), online: amount('online', true) };
  if (errors.length) throw new Error(`Fix the arguments:\n  - ${errors.join('\n  - ')}`);
  return input;
}

async function main() {
  const input = readInput();
  const { date } = input;
  const month = date.slice(0, 7);
  const year = date.slice(0, 4);

  initializeApp({ credential: cert(require(KEY_PATH)) });
  const db = getFirestore();
  const reports = db.collection('DailyFinancialReport');
  const dayStart = Timestamp.fromDate(new Date(`${date}T00:00:00+07:00`));
  const dayEnd = Timestamp.fromMillis(dayStart.toMillis() + 24 * 3600e3);

  const refs = {
    daily: reports.doc(date),
    monthly: db.collection('MonthlyFinancialReport').doc(month),
    yearly: db.collection('YearlyFinancialReport').doc(year),
  };
  const [sales, existing, prevSnap, laterSnap, expenseSnap, monthlySnap, yearlySnap] = await Promise.all([
    db.collection('DailyTransaction').doc(date).get(),
    refs.daily.get(),
    reports.where(FieldPath.documentId(), '<', date).orderBy(FieldPath.documentId(), 'desc').limit(1).get(),
    reports.where(FieldPath.documentId(), '>', date).limit(1).get(),
    db.collection('Expenses').where('timestamp', '>=', dayStart).where('timestamp', '<', dayEnd).get(),
    refs.monthly.get(),
    refs.yearly.get(),
  ]);

  const blockers = [];
  if (existing.exists) blockers.push(`DailyFinancialReport/${date} already exists; this script only creates missing closings.`);
  if (!laterSnap.empty) {
    blockers.push(`A later day (${laterSnap.docs[0].id}) is already closed; its balances were built without ${date}. Fix those by hand.`);
  }
  if (!sales.exists) blockers.push(`DailyTransaction/${date} does not exist, so there were no sales to close.`);

  // ---- Same figures the app's _submitReport works out ----
  const s = sales.data() || {};
  const system = { Cash: toInt(s.totalCash), Qris: toInt(s.totalQris), Online: toInt(s.totalOnline) };
  const actual = { Cash: input.cash, Qris: input.qris, Online: input.online ?? system.Online };

  // The app's sheet ignores expenses added from the web dashboard (addedFromDashboardWeb) ...
  const expenses = expenseSnap.docs.map((d) => d.data());
  const sumBy = (list, account) => list.filter((e) => e.sourceAccount === account).reduce((t, e) => t + toInt(e.amount), 0);
  const posExpenses = expenses.filter((e) => e.addedFromDashboardWeb !== true);
  const expense = Object.fromEntries(ACCOUNTS.map(([f, a]) => [f, sumBy(posExpenses, a)]));
  // ... but the dashboard's balance sync takes every expense off the running balance.
  const allExpense = Object.fromEntries(ACCOUNTS.map(([f, a]) => [f, sumBy(expenses, a)]));

  const discrepancy = Object.fromEntries(ACCOUNTS.map(([f]) => [f, actual[f] - (system[f] - expense[f])]));

  // closing* follows the dashboard's sync convention (prev closing + sales + discrepancy - every expense),
  // which is what its cashflow page and syncDailyFinancialReportsWithOpeningBalance store.
  const prev = prevSnap.empty ? {} : prevSnap.docs[0].data();
  const closing = Object.fromEntries(
    ACCOUNTS.map(([f]) => [f, toInt(prev[`closing${f}`]) + system[f] + discrepancy[f] - allExpense[f]]),
  );

  const b2bRedeemed = toInt(s.totalB2BRedeemed ?? s.totalVoucher);
  const b2bSettled = toInt(s.totalB2BSettled ?? s.totalVoucherSettled);

  // 16:00 WIB: when the cashier normally closes. Nothing reads it; it only keeps the doc inside its own day.
  const closedAt = Timestamp.fromDate(new Date(`${date}T16:00:00+07:00`));

  const figures = {
    ...Object.fromEntries(ACCOUNTS.map(([f]) => [`systemSales${f}`, system[f]])),
    totalVoucher: b2bRedeemed,
    totalVoucherSettled: b2bSettled,
    totalB2BRedeemed: b2bRedeemed,
    totalB2BSettled: b2bSettled,
    ...Object.fromEntries(ACCOUNTS.map(([f]) => [`expenses${f}`, expense[f]])),
    ...Object.fromEntries(ACCOUNTS.map(([f]) => [`actual${f}`, actual[f]])),
    ...Object.fromEntries(ACCOUNTS.map(([f]) => [`discrepancy${f}`, discrepancy[f]])),
  };
  const closingFields = Object.fromEntries(ACCOUNTS.map(([f]) => [`closing${f}`, closing[f]]));

  // ---- Print the plan ----
  console.log(`\nClose ${date} (WIB) from counted amounts`);
  console.log(`  ${'account'.padEnd(8)} ${'system'.padStart(12)} ${'counted'.padStart(12)} ${'discrepancy'.padStart(12)} ${'prev close'.padStart(12)} ${'new close'.padStart(12)}`);
  for (const [f] of ACCOUNTS) {
    console.log(
      `  ${f.padEnd(8)} ${rp(system[f]).padStart(12)} ${rp(actual[f]).padStart(12)} ${rp(discrepancy[f]).padStart(12)} ${rp(toInt(prev[`closing${f}`])).padStart(12)} ${rp(closing[f]).padStart(12)}`,
    );
  }
  console.log(`  previous closing taken from: ${prevSnap.empty ? '(none; starting from 0)' : `DailyFinancialReport/${prevSnap.docs[0].id}`}`);
  console.log(`  expenses that day: ${expenses.length} (${posExpenses.length} from the POS, ${expenses.length - posExpenses.length} from the dashboard)`);
  for (const [f] of ACCOUNTS) {
    if (allExpense[f] || expense[f]) console.log(`    ${f}: POS ${rp(expense[f])} (stored as expenses${f}), all sources ${rp(allExpense[f])} (taken off the closing balance)`);
  }
  console.log(`  B2B redeemed ${rp(b2bRedeemed)}, settled ${rp(b2bSettled)}`);

  console.log('\nMonthly / yearly report increments:');
  for (const [label, snap] of [[`MonthlyFinancialReport/${month}`, monthlySnap], [`YearlyFinancialReport/${year}`, yearlySnap]]) {
    const data = snap.data() || {};
    console.log(`  ${label}${snap.exists ? '' : ' (new)'}`);
    for (const [field, delta] of Object.entries(figures)) {
      if (!delta && field.startsWith('total')) continue;
      console.log(`      ${field.padEnd(22)} ${rp(toInt(data[field]))} -> ${rp(toInt(data[field]) + delta)}`);
    }
    for (const [field, value] of Object.entries(closingFields)) {
      console.log(`      ${field.padEnd(22)} ${rp(toInt(data[field]))} -> ${rp(value)}  (overwritten, as the app does)`);
    }
  }

  for (const b of blockers) console.log(`\nBLOCKED: ${b}`);
  if (blockers.length) {
    process.exitCode = 1;
    return;
  }
  if (!APPLY) {
    console.log('\nDry run only; nothing was written. Re-run with --apply to write.');
    return;
  }

  await db.runTransaction(async (tx) => {
    if ((await tx.get(refs.daily)).exists) throw new Error(`DailyFinancialReport/${date} was created in the meantime.`);

    const increments = Object.fromEntries(Object.entries(figures).map(([k, v]) => [k, FieldValue.increment(v)]));
    tx.create(refs.daily, {
      date,
      month,
      ...figures,
      ...closingFields,
      timestamp: closedAt,
      isBackfill: true,
      backfilledAt: FieldValue.serverTimestamp(),
    });
    tx.set(refs.monthly, { month, ...increments, ...closingFields, lastUpdated: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(refs.yearly, { year, ...increments, ...closingFields, lastUpdated: FieldValue.serverTimestamp() }, { merge: true });
  });

  console.log('\nApplied. DailyFinancialReport now:');
  const done = (await refs.daily.get()).data();
  for (const k of Object.keys({ ...figures, ...closingFields })) console.log(`  ${k.padEnd(22)} ${rp(done[k])}`);
}

main().catch((err) => {
  console.error(`\nFAILED: ${err.message}`);
  process.exitCode = 1;
});
