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

**Message Reply**:
A Channel message that references exactly one earlier message in the same
Channel and remains part of the normal Channel timeline.
_Avoid_: Direct reply, thread

**User Mention**:
An explicit `@username` reference to a Workspace Member within a Channel
message.
_Avoid_: Implicit reply mention, ping

**Everyone Mention**:
An explicit `@everyone` reference that addresses the Workspace-wide audience
from within a Channel message.
_Avoid_: User mention, role mention

**Activity Feed**:
A User's global collection of relevant activity across every Workspace in
which they participate.
_Avoid_: Workspace activity, Activity Page

**Activity Item**:
A durable mention entry in a User's Activity Feed that links to its source
message and records whether the User has read it.
_Avoid_: Notification

**Landing Channel**:
The default channel a user should enter when opening or joining a workspace.
New workspaces start with a `general` landing channel, and later renaming that
channel does not change its landing role because the role is tied to the
channel ID.
_Avoid_: Main channel, default page

**Workspace Entry**:
The workflow of opening a workspace and navigating to its landing channel.
_Avoid_: Workspace details page

**Read State**:
A Workspace Member's per-Channel read position and cached unread summary,
including unread count and first/last unread message sequence bounds.
_Avoid_: Read receipt

**Unread Span**:
An inclusive `{from_seq, to_seq}` interval of unread message sequences for one
User and Channel.
_Avoid_: Unread range

## Relationships

- A **User** may own many **Workspaces**
- A **Workspace Identifier** points to one **Workspace**
- A **Workspace** has zero or more **Workspace Members**
- A **Workspace Member** has one **Workspace Role**
- A **Workspace** contains one or more **Channels** when created through the
  public workspace workflow
- A **Message Reply** references a message in the same **Channel**
- A **Message Reply** does not create a thread or nested conversation
- A **Message Reply** may reference another **Message Reply**, but preserves only
  one direct reference rather than a reply chain
- A **Message Reply** does not implicitly create a **User Mention** for the
  referenced message's author
- Channel messages support **User Mentions** and **Everyone Mentions**, but not
  role or Channel mentions
- Only Workspace owners and admins may create an **Everyone Mention**; an
  `@everyone` written by a regular Workspace Member remains plain message text
- `everyone` is reserved and cannot be used as a User's username
- Mention recipients are resolved when a message is sent; username changes and
  later Workspace membership changes do not retarget that message
- A User's **Activity Feed** spans all of their Workspaces rather than the
  currently selected Workspace
- A User's **Activity Feed** includes **User Mentions** addressed to that User
  and authorized **Everyone Mentions** in their Workspaces
- A User's own messages never create entries in that User's **Activity Feed**
- Opening an **Activity Item** navigates to its source message in the source
  Workspace and Channel and marks that item as read
- Opening the **Activity Feed** does not itself mark **Activity Items** as read
- A User may mark every **Activity Item** as read, and the activity bell count
  reflects unread items
- **Activity Item** read state is independent from Channel **Read State**;
  changing either one does not automatically clear the other
- Losing Workspace membership permanently removes that Workspace's entries from
  the former member's **Activity Feed**
- Deleting the message referenced by a **Message Reply** preserves the reply and
  replaces its quoted preview with a deleted-message placeholder
- A deleted message cannot become the target of a new **Message Reply**
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
- A **Landing Channel** is the channel stored on the **Workspace** as its
  default channel
- **Workspace Entry** redirects to the **Landing Channel**
- Resolving a **Landing Channel** is a scoped **Workspace Entry** workflow, not
  part of **Channel** creation
- A **Read State** belongs to one **User** and one **Channel**
- A **Read State** summarizes zero or more **Unread Spans**
- An **Unread Span** belongs to one **User** and one **Channel**

## Example Dialogue

> **Dev:** "Can any logged-in **User** create a **Channel** in a **Workspace**?"
> **Domain expert:** "For now, yes. Later we will use **Workspace Roles** so only admin-like members can manage channels and members."
>
> **Dev:** "Does creating the first **Channel** make it the **Landing Channel**?"
> **Domain expert:** "No. Workspace creation creates the `general` **Landing Channel**. Creating additional **Channels** only creates channels and does not change the landing channel."

## Flagged Ambiguities

- "Authorized" is the canonical spelling for permission outcomes in code and
  docs. Use `:unauthorized` for a logged-in user who lacks access.
- Channel creation distinguishes identity, permission, and existence failures:
  anonymous users are unauthenticated, logged-in non-members are unauthorized,
  and missing workspaces are not found.
