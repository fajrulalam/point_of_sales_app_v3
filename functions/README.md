# Retired deployment source

The production `distributeMonthlyRewards` scheduler is owned by the sibling
Membership_App repository, `functions/src/competitionRewards.ts`, Firebase
codebase `member-registration`. This directory is retained for historical
reference and is excluded from the POS Firebase deployment configuration.
Its deployment command intentionally fails. Do not restore the old category
scheduler or deploy it under the `default` codebase.

POS manual finalization lives in `lib/Services/MemberProgramService.dart`.
Both implementations use the global competition policy from September 2026.
