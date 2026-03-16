import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

// Set global options to use a specific region if needed, 
// and ensure we use the correct service account permissions
// admin.initializeApp(); <-- Assuming this is already called elsewhere in your index.ts
setGlobalOptions({ region: "us-central1" }); // Choose your closest region

/**
 * Autonomous Monthly Reward Distribution
 * Triggers: 1st day of every month at 00:00
 * Logic:
 * 1. Identify previous month ID (YYYY-MM).
 * 2. Fetch competition records for that month.
 * 3. Group participants by their Member category.
 * 4. Rank them and distribute vouchers to Top 3 (25k, 15k, 10k).
 */
export const distributeMonthlyRewards = onSchedule("0 0 1 * *", async (event) => {
    const db = admin.firestore();

    // 1. Determine the target month (the month that just finished)
    const now = new Date();
    const prevMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const prevMonthStr = `${prevMonthDate.getFullYear()}-${String(prevMonthDate.getMonth() + 1).padStart(2, "0")}`;

    console.log(`🚀 Starting Monthly Reward distribution for: ${prevMonthStr}`);

    try {
        // 2. Load data from competitionRecords and Members
        const [compDoc, membersSnap] = await Promise.all([
            db.collection("competitionRecords").doc(prevMonthStr).get(),
            db.collection("Members").get(),
        ]);

        if (!compDoc.exists) {
            console.log("ℹ️ No competition records found for last month. Skipping.");
            return;
        }

        const records = compDoc.data() || {};
        const memberMap = new Map();
        membersSnap.forEach((doc) => memberMap.set(doc.id, doc.data()));

        // 3. Group participants by Category
        const categoriesMap = new Map<string, any[]>();

        for (const [memberId, stats] of Object.entries(records)) {
            const memberData = memberMap.get(memberId);
            if (!memberData) continue;

            const category = memberData.category || "Umum";
            const points = (stats as any).customerPoints || 0;

            if (points > 0) {
                if (!categoriesMap.has(category)) categoriesMap.set(category, []);
                categoriesMap.get(category)!.push({
                    id: memberId,
                    name: memberData.fullName || memberData.name || "Member",
                    points: points,
                });
            }
        }

        // 4. Configuration for prizes
        const prizes = [25000, 15000, 10000]; // UPDATED: 1st (25k), 2nd (15k), 3rd (10k)
        const batch = db.batch();
        const currentMonthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

        let totalVouchers = 0;

        // Helper to generate 4-character uppercase alphanumeric ID
        const generateShortId = () => {
            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
            let randomCode = '';
            for (let i = 0; i < 4; i++) {
                randomCode += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            return randomCode;
        };

        // 5. Process each category and rank members
        for (const [category, participants] of categoriesMap.entries()) {
            // Sort: Highest points first
            participants.sort((a, b) => b.points - a.points);

            const winners = participants.slice(0, 3);
            winners.forEach((winner, index) => {
                const rank = index + 1;
                const prizeValue = prizes[index];
                
                // Create a random 4-char string for voucherId
                const shortVoucherId = generateShortId();
                const newVoucherRef = db.collection("vouchers").doc(); // Keep a strong backend ID

                batch.set(newVoucherRef, {
                    userId: winner.id,
                    nama: winner.name,
                    type: "competitionReward",
                    value: prizeValue,
                    status: "READY_TO_CLAIM",
                    transactionRequirement: 10000, // ADDED: Transaction requirement
                    activeDate: admin.firestore.Timestamp.fromDate(now),
                    expireDate: admin.firestore.Timestamp.fromDate(currentMonthEnd),
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    voucherName: `Juara ${rank} ${category} - ${prevMonthStr}`,
                    voucherId: shortVoucherId, // UPDATED: 4-char format
                });

                totalVouchers++;
            });
        }

        // 6. Execute all writes atomicly
        if (totalVouchers > 0) {
            await batch.commit();
            console.log(`✅ Success! Distributed ${totalVouchers} reward vouchers.`);
        } else {
            console.log("ℹ️ No eligible winners found this month.");
        }
    } catch (error) {
        console.error("❌ Error during reward distribution:", error);
    }
});
