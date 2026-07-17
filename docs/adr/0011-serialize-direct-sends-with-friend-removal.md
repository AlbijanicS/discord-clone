# Serialize Direct Message sends with Friend removal

Direct Message sends take a shared lock on the accepted Friend relationship before locking the Conversation, while Friend removal takes an exclusive relationship lock. Whichever transaction obtains the relationship lock first determines whether the final Message is permitted, and all Direct Message workflows follow the lock order `Friend relationship → Conversation → Read State` to avoid authorization races and deadlocks without coupling Chat to the FriendRelationship schema directly.
