# Model Conversation kinds with shared-primary-key subtypes

Shared message mechanics live under a `conversations` base table, while `channels` and `direct_conversations` hold kind-specific identity using `conversation_id` as both primary key and foreign key to the base. Messages, sequencing, runtime processes, and read state reference the Conversation ID; subtype rows retain clean Workspace and participant constraints without nullable kind-specific columns in the base table, and each base/subtype pair is created atomically.
