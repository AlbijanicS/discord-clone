# Synchronize Direct Message activity with visibility

Every received Direct Message creates an Activity Item as well as Conversation unread state. After the Message remains genuinely visible for one continuous second, one transaction updates both representations: the Message leaves unread spans and its Activity Item becomes read; the primary unread activity view hides it while durable Activity history retains it. Mention Activity Items keep their existing independence from Channel Read State.
