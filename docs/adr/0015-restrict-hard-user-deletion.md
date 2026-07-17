# Restrict hard User deletion

Hard User deletion is out of scope once Direct Conversations exist because their canonical participant pair and preserved history require stable User IDs. Direct Conversation participant foreign keys restrict deletion; a future account-removal feature must deliberately deactivate or anonymize the User while preserving durable identity rather than cascading away conversation history or weakening participant constraints.
