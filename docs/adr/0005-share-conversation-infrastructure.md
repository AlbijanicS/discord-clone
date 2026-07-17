# Share conversation infrastructure between Channels and Direct Conversations

Workspace Channels and Direct Conversations use a shared Conversation foundation for messages, sequencing, runtime caching, typing, reactions, replies, and unread state while retaining separate authorization and recipient policies. Direct Messages appear as a top-level destination in the interface but are not represented by a synthetic Workspace; because the project has no persistent data to preserve, the schema may be reshaped directly instead of carrying compatibility-oriented message ownership.
