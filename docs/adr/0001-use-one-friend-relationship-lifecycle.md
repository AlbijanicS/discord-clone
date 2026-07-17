# Use one record for the Friend relationship lifecycle

Friend Requests and Friendships are stored as states of one canonical relationship record per pair of Users rather than in separate request and friendship tables. This keeps pair uniqueness and request acceptance atomic, prevents pending and accepted relationships from coexisting, and makes crossed requests straightforward; the negligible extra status predicate on friendship reads is preferred over a cross-table invariant.
