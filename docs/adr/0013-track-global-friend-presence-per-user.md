# Track global Friend Presence per User

Global Friend Presence is ephemeral online/offline state owned by one dynamically supervised `UserPresenceServer` per connected User, independent from existing Workspace-scoped presence. Each server monitors all authenticated LiveView connections for its User, broadcasts edge transitions between zero and nonzero connections, and stops after the final connection exits; only current Friends may subscribe, and no presence history or richer status is persisted.
