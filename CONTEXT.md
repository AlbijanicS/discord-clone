# Discord Clone

This context describes the collaboration domain for the Discord clone: users
create workspaces, join them through memberships, organize conversation into
channels, and later exchange messages in those channels.

## Language

**User**:
A person with an account that can authenticate and participate in workspaces.
_Avoid_: Account

**Workspace**:
The top-level collaboration space that contains members and channels.
_Avoid_: Server

**Workspace Identifier**:
A value that identifies which workspace a workflow should act on.
_Avoid_: Workspace object, workspace param

**Workspace Member**:
A user who has permission to participate in a workspace through membership.
_Avoid_: Participant

**Workspace Role**:
A named permission level held by a workspace member.
_Avoid_: Global role

**Channel**:
A named conversation space inside a workspace.
_Avoid_: Room

**Landing Channel**:
The channel a user should enter when opening or joining a workspace.
_Avoid_: Main channel, default page

## Relationships

- A **User** may own many **Workspaces**
- A **Workspace Identifier** points to one **Workspace**
- A **Workspace** has zero or more **Workspace Members**
- A **Workspace Member** has one **Workspace Role**
- A **Workspace** contains zero or more **Channels**
- A **Workspace Member** may create **Channels** until role-specific channel
  permissions are introduced
- A **User** who is not a **Workspace Member** must not be able to view or
  mutate that **Workspace**
- Creating a **Channel** does not select or change the **Landing Channel**
- Creating a **Channel** returns the created **Channel**, not workspace landing
  metadata
- A **Channel** creation workflow takes its **Workspace** from the explicit
  **Workspace Identifier**, not from form attributes
- A **Channel** creation workflow requires an explicit valid channel name
- Invalid **Channel** creation input is reported as an explicit channel
  validation error, `:invalid_channel`, that still carries field-level
  validation details
- Channel forms are backed by a public workspace-context change workflow rather
  than direct schema access from the web layer
- A **Landing Channel** is the explicitly selected default channel when one is
  set, otherwise the oldest **Channel** in the **Workspace**
- Resolving a **Landing Channel** is a scoped navigation workflow, not part of
  **Channel** creation

## Example Dialogue

> **Dev:** "Can any logged-in **User** create a **Channel** in a **Workspace**?"
> **Domain expert:** "For now, yes. Later we will use **Workspace Roles** so only admin-like members can manage channels and members."
>
> **Dev:** "Does creating the first **Channel** make it the **Landing Channel**?"
> **Domain expert:** "No. Creating a **Channel** only creates the **Channel**; landing falls back to the oldest **Channel** until a default is explicitly selected."

## Flagged Ambiguities

- "Authorized" is the canonical spelling for permission outcomes in code and
  docs. Use `:unauthorized` for a logged-in user who lacks access.
- Channel creation distinguishes identity, permission, and existence failures:
  anonymous users are unauthenticated, logged-in non-members are unauthorized,
  and missing workspaces are not found.
