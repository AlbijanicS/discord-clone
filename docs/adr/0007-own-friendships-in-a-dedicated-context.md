# Own Friendships in a dedicated context

`DiscordClone.Friendships` owns Friend Requests, Friendships, relationship queries, and their lifecycle rather than extending the generated `Accounts` context. Accounts remains responsible for User identity and authentication, while Chat depends on Friendships for Direct Message send authorization, preserving the dependency direction `Chat → Friendships → Accounts`.
