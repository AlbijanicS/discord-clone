# Keep Conversation runtime independent from Friendship policy

An open Direct Conversation remains subscribed and visible when its Friendship ends, while private Friendship events make the LiveView immediately recompute capabilities, stop typing, hide Friend Presence, and enter read-only mode; restoring the Friendship reverses that state in the same Conversation. ConversationServer owns only ephemeral conversation mechanics, while every mutation remains authorized through Chat and Friendships so stale clients cannot bypass the new policy.
