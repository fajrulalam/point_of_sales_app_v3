#!/usr/bin/env node
// Backfills a sale that was never entered at the till. See docs/backfill_missed_sales.md.
//
//   node scripts/backfill_order.js scripts/backfills/<file>.js            # dry run: reads only
//   node scripts/backfill_order.js scripts/backfills/<file>.js --apply    # writes in one transaction

const path = require('path');
const { createRequire } = require('module');

const ROOT = path.join(__dirname, '..');
const requireFromFunctions = createRequire(path.join(ROOT, 'functions', 'package.json'));
const { initializeApp, cert } = requireFromFunctions('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = requireFromFunctions('firebase-admin/firestore');

const KEY_PATH = path.join(ROOT, 'point-of-sales-app-25e2b-firebase-adminsdk-isjye-3ddd9cdd88.json');

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const FORCE = args.includes('--force');
const configArg = args.find((a) => !a.startsWith('--'));

const PAYMENT_METHODS = ['Cash', 'QRIS', 'Online', 'Cash + QRIS'];
const TOTAL_FIELD = { Cash: 'totalCash', QRIS: 'totalQris', Online: 'totalOnline' };
const REPORT_SUFFIX = { Cash: 'Cash', QRIS: 'Qris', Online: 'Online' };

const rp = (n) => `Rp ${Number(n || 0).toLocaleString('id-ID')}`;
const toInt = (v) => (typeof v === 'number' ? Math.trunc(v) : parseInt(v, 10) || 0);
const isPositiveInt = (v) => Number.isInteger(v) && v > 0;
const slug = (s) => s.replace(/[^a-zA-Z0-9]+/g, '_');

function loadOrder() {
  if (!configArg) {
    throw new Error('Usage: node scripts/backfill_order.js scripts/backfills/<file>.js [--apply] [--force]');
  }
  const order = require(path.resolve(configArg));
  const errors = [];

  const wib = (d) => (isNaN(d) ? '' : new Date(d.getTime() + 7 * 3600e3).toISOString());
  const saleAt = new Date(`${order.date}T${order.time}:00+07:00`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(order.date) || wib(new Date(`${order.date}T00:00:00+07:00`)).slice(0, 10) !== order.date) {
    errors.push(`date must be a real day written as YYYY-MM-DD (got "${order.date}")`);
  } else if (!/^\d{2}:\d{2}$/.test(order.time) || wib(saleAt).slice(11, 16) !== order.time) {
    errors.push(`time must be HH:mm (got "${order.time}")`);
  } else if (saleAt > new Date()) {
    errors.push('date/time is in the future');
  }

  if (!Array.isArray(order.items) || order.items.length === 0) {
    errors.push('items must list at least one item');
  } else {
    const seen = new Set();
    for (const item of order.items) {
      if (typeof item.menuName !== 'string' || !item.menuName.trim()) errors.push('every item needs a menuName');
      if (!isPositiveInt(item.quantity)) errors.push(`"${item.menuName}": quantity must be a whole number above 0`);
      if (item.unitPrice !== undefined && !isPositiveInt(item.unitPrice)) {
        errors.push(`"${item.menuName}": unitPrice must be a whole number above 0, or left out`);
      }
      if (seen.has(item.menuName)) errors.push(`"${item.menuName}" is listed twice; combine the quantities`);
      seen.add(item.menuName);
    }
  }
  if (!Number.isInteger(order.takeAwayFee ?? 0) || (order.takeAwayFee ?? 0) < 0) {
    errors.push('takeAwayFee must be a whole number, 0 or more');
  }
  if (!PAYMENT_METHODS.includes(order.paymentMethod)) {
    errors.push(`paymentMethod must be one of ${PAYMENT_METHODS.map((m) => `'${m}'`).join(', ')}`);
  }
  if (![null, undefined, true, false].includes(order.moneyWasCountedInClosing)) {
    errors.push('moneyWasCountedInClosing must be true, false or null');
  }
  if (typeof order.reason !== 'string' || !order.reason.trim()) errors.push('reason is required');

  if (errors.length) throw new Error(`Fix ${configArg}:\n  - ${errors.join('\n  - ')}`);
  return { ...order, takeAwayFee: order.takeAwayFee ?? 0, saleAt: Timestamp.fromDate(saleAt) };
}

async function main() {
  const order = loadOrder();
  initializeApp({ credential: cert(require(KEY_PATH)) });
  const db = getFirestore();
  const canteen = db.collection('Canteens').doc('canteen375');

  // ---- Resolve menu items and amounts ----
  const menus = (await canteen.collection('MenuCollection').get()).docs;
  const notes = [];
  const lines = order.items.map((item) => {
    const matches = menus.filter((m) => m.get('namaMenu') === item.menuName);
    if (matches.length !== 1) {
      const words = item.menuName.toLowerCase().split(/\s+/).filter((w) => w.length >= 3);
      const similar = menus
        .map((m) => String(m.get('namaMenu') ?? ''))
        .filter((name) => words.some((w) => name.toLowerCase().includes(w)));
      throw new Error(
        matches.length
          ? `${matches.length} menus are named "${item.menuName}"; rename one in the app first.`
          : `No menu named exactly "${item.menuName}".${similar.length ? ` Similar: ${similar.map((s) => `"${s}"`).join(', ')}` : ''}`,
      );
    }
    const menu = matches[0].data();
    const menuPrice = toInt(menu.harga);
    const unitPrice = item.unitPrice ?? menuPrice;
    if (unitPrice !== menuPrice) {
      notes.push(`"${menu.namaMenu}" is recorded at ${rp(unitPrice)}; the current menu price is ${rp(menuPrice)}.`);
    }
    const ingredients = Array.isArray(menu.ingredients) ? menu.ingredients : [];
    return { name: menu.namaMenu, menuId: matches[0].id, quantity: item.quantity, unitPrice, ingredients };
  });

  const itemsTotal = lines.reduce((sum, l) => sum + l.quantity * l.unitPrice, 0);
  const total = itemsTotal + order.takeAwayFee;
  let payments;
  if (order.paymentMethod === 'Cash + QRIS') {
    if (!isPositiveInt(order.qrisAmount) || order.qrisAmount >= total) {
      throw new Error(`qrisAmount must be above 0 and below the order total ${rp(total)} for 'Cash + QRIS'.`);
    }
    payments = { Cash: total - order.qrisAmount, QRIS: order.qrisAmount };
  } else {
    payments = { [order.paymentMethod]: total };
  }

  const month = order.date.slice(0, 7);
  const year = order.date.slice(0, 4);
  const operationId =
    `backfill-sale--${order.date}-${order.time.replace(':', '')}-${total}-${slug(order.paymentMethod)}--` +
    lines.map((l) => `${slug(l.name)}_${l.quantity}_${l.unitPrice}`).join('_');

  const ledgerRef = canteen.collection('Orders').doc(operationId);
  const memberOpRef = db.collection('memberProgramOperations').doc(operationId);
  const dailyRef = db.collection('DailyTransaction').doc(order.date);
  const monthlyRef = db.collection('MonthlyTransaction').doc(month);
  const yearlyRef = db.collection('YearlyTransaction').doc(year);
  const dailyReportRef = db.collection('DailyFinancialReport').doc(order.date);
  const monthlyReportRef = db.collection('MonthlyFinancialReport').doc(month);
  const yearlyReportRef = db.collection('YearlyFinancialReport').doc(year);

  const [dailySnap, monthlySnap, yearlySnap, dailyReportSnap, monthlyReportSnap, yearlyReportSnap, ledgerSnap, sameDateSnap] =
    await Promise.all([
      ...[dailyRef, monthlyRef, yearlyRef, dailyReportRef, monthlyReportRef, yearlyReportRef, ledgerRef].map((r) => r.get()),
      canteen.collection('Orders').where('sale.date', '==', order.date).get(),
    ]);

  // ---- Print the plan ----
  const salesFields = [
    ['total', total],
    ...Object.entries(payments).map(([m, a]) => [TOTAL_FIELD[m], a]),
    ...(order.takeAwayFee ? [['takeAwayFee', order.takeAwayFee]] : []),
    ...lines.map((l) => [l.name, l.quantity, true]),
  ];
  const reportFields = Object.entries(payments).flatMap(([m, a]) => [
    [`actual${REPORT_SUFFIX[m]}`, null],
    [`systemSales${REPORT_SUFFIX[m]}`, a],
    [`discrepancy${REPORT_SUFFIX[m]}`, -a],
  ]);
  const printDoc = (label, snap, fields, planned) => {
    const data = snap.data() || {};
    console.log(`  ${label}${snap.exists ? '' : ' (new)'}`);
    for (const [field, delta, isCount] of fields) {
      const fmt = isCount ? String : rp;
      const before = toInt(data[field]);
      const after = planned && delta !== null ? ` -> ${fmt(before + delta)}` : '';
      console.log(`      ${(isCount ? `"${field}"` : field).padEnd(28)} ${fmt(before)}${after}`);
    }
  };

  console.log(`\nBackfill: ${order.date} ${order.time} WIB, paid ${order.paymentMethod}`);
  for (const l of lines) console.log(`  ${l.quantity} x ${l.name} @ ${rp(l.unitPrice)} = ${rp(l.quantity * l.unitPrice)}`);
  if (order.takeAwayFee) console.log(`  take-away fee ${rp(order.takeAwayFee)}`);
  console.log(`  total ${rp(total)}  (${Object.entries(payments).map(([m, a]) => `${m} ${rp(a)}`).join(', ')})`);
  for (const l of lines.filter((l) => l.ingredients.length)) {
    notes.push(`"${l.name}" uses stock ingredients; stock is NOT changed by this script: ${JSON.stringify(l.ingredients)}`);
  }
  console.log(`  reason: ${order.reason}`);
  console.log(`  audit id: Canteens/canteen375/Orders/${operationId}`);

  if (ledgerSnap.exists) {
    console.log('\nThis exact backfill was already applied. Nothing to do. Current totals:');
    printDoc(`DailyTransaction/${order.date}`, dailySnap, salesFields, false);
    return;
  }

  const hasClosing = dailyReportSnap.exists;
  const adjustClosing = hasClosing && order.moneyWasCountedInClosing === true;
  const blockers = [];

  const otherBackfills = sameDateSnap.docs.filter((d) => d.get('isBackfill') === true);
  if (otherBackfills.length) {
    blockers.push(
      `Another backfill already exists for ${order.date}:\n` +
        otherBackfills.map((d) => `      ${d.id}  (${rp(d.get('sale.total'))})`).join('\n') +
        '\n    If this is a different sale, re-run with --force.',
    );
  }
  if (hasClosing && dailyReportSnap.get('isDiscrepancyConfirmed') === true) {
    blockers.push(
      `The closing discrepancy for ${order.date} was already confirmed on the dashboard. Older dashboard versions add\n` +
        '    confirmed discrepancies into the sales totals, which would count this sale twice. Check that day\'s sales\n' +
        '    total first; if it does not already include this sale, re-run with --force.',
    );
  }

  console.log('\nSales totals (before -> after):');
  printDoc(`DailyTransaction/${order.date}`, dailySnap, salesFields, true);
  printDoc(`MonthlyTransaction/${month}`, monthlySnap, salesFields, true);
  printDoc(`YearlyTransaction/${year}`, yearlySnap, salesFields, true);

  console.log('\nEnd-of-day closing:');
  if (!hasClosing) {
    console.log(`  ${order.date} has no closing, so there is nothing to adjust.`);
    console.log('  The cashflow page will not include this money (see the docs).');
  } else if (order.moneyWasCountedInClosing == null) {
    console.log(`  ${order.date} already has a closing. Current numbers:`);
    printDoc(`DailyFinancialReport/${order.date}`, dailyReportSnap, reportFields, false);
    throw new Error(
      'Set moneyWasCountedInClosing to true or false in the config (see the docs). A discrepancy of about\n' +
        '  +the sale amount above usually means the money was counted.',
    );
  } else if (adjustClosing) {
    console.log('  Money was counted at closing: sales side goes up, discrepancy goes down. Balances unchanged.');
    printDoc(`DailyFinancialReport/${order.date}`, dailyReportSnap, reportFields, true);
    printDoc(`MonthlyFinancialReport/${month}`, monthlyReportSnap, reportFields, true);
    printDoc(`YearlyFinancialReport/${year}`, yearlyReportSnap, reportFields, true);
  } else {
    console.log('  Money was NOT counted at closing: the closing is left as is.');
    console.log('  The cashflow page will not include this money (see the docs).');
  }

  for (const n of notes) console.log(`\nNOTE: ${n}`);
  for (const b of blockers) console.log(`\nBLOCKED: ${b}`);

  if (!APPLY) {
    console.log('\nDry run only; nothing was written. Re-run with --apply to write.');
    return;
  }
  if (blockers.length && !FORCE) {
    console.log('\nNot applied.');
    process.exitCode = 1;
    return;
  }

  await db.runTransaction(async (tx) => {
    const [txLedger, txDaily, txDailyReport, txMonthlyReport, txYearlyReport] = await Promise.all(
      [ledgerRef, dailyRef, dailyReportRef, monthlyReportRef, yearlyReportRef].map((r) => tx.get(r)),
    );
    if (txLedger.exists) throw new Error('This backfill was applied in the meantime.');
    if (txDailyReport.exists !== hasClosing) throw new Error('The closing for that day changed in the meantime; run again.');

    const salesDelta = {
      total: FieldValue.increment(total),
      subTotal: FieldValue.increment(itemsTotal),
      takeAwayFee: FieldValue.increment(order.takeAwayFee),
    };
    for (const [m, a] of Object.entries(payments)) salesDelta[TOTAL_FIELD[m]] = FieldValue.increment(a);
    for (const l of lines) salesDelta[l.name] = FieldValue.increment(l.quantity);
    tx.set(
      dailyRef,
      { ...salesDelta, year, month, date: order.date, ...(txDaily.exists ? {} : { timestamp: order.saleAt }) },
      { merge: true },
    );
    tx.set(monthlyRef, salesDelta, { merge: true });
    tx.set(yearlyRef, salesDelta, { merge: true });

    if (adjustClosing) {
      const reportDelta = {};
      for (const [m, a] of Object.entries(payments)) {
        reportDelta[`systemSales${REPORT_SUFFIX[m]}`] = FieldValue.increment(a);
        reportDelta[`discrepancy${REPORT_SUFFIX[m]}`] = FieldValue.increment(-a);
      }
      for (const snap of [txDailyReport, txMonthlyReport, txYearlyReport]) {
        if (snap.exists) tx.set(snap.ref, reportDelta, { merge: true });
      }
    }

    tx.set(memberOpRef, {
      schemaVersion: 2,
      operationId,
      status: 'skipped',
      reason: 'member_not_selected',
      auditFlags: [],
      completedAt: order.saleAt,
    });
    tx.set(ledgerRef, {
      status: 'completed',
      type: 'sale',
      auditFlags: [],
      completedAt: order.saleAt,
      isBackfill: true,
      backfilledAt: FieldValue.serverTimestamp(),
      reason: order.reason,
      sale: {
        date: order.date,
        time: order.time,
        items: lines.map((l) => ({ menuName: l.name, menuItemId: l.menuId, quantity: l.quantity, unitPrice: l.unitPrice })),
        takeAwayFee: order.takeAwayFee,
        total,
        paymentMethod: order.paymentMethod,
        payments,
        closingAdjusted: adjustClosing,
      },
    });
  });

  console.log('\nApplied. Totals now:');
  printDoc(`DailyTransaction/${order.date}`, await dailyRef.get(), salesFields, false);
  printDoc(`MonthlyTransaction/${month}`, await monthlyRef.get(), salesFields, false);
  printDoc(`YearlyTransaction/${year}`, await yearlyRef.get(), salesFields, false);
  if (adjustClosing) printDoc(`DailyFinancialReport/${order.date}`, await dailyReportRef.get(), reportFields, false);
}

main().catch((err) => {
  console.error(`\nFAILED: ${err.message}`);
  process.exitCode = 1;
});
