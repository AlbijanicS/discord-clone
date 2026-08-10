# Discord Clone

This context describes the collaboration domain for the Discord clone: Users
create Workspaces, join them through memberships, and exchange Messages in
Workspace Channels or one-to-one Direct Conversations.

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

**Friend Request**:
A User's pending request to establish a mutual Friendship with another User.
_Avoid_: Pending friend, friend invitation

**Friendship**:
An accepted, mutual relationship between exactly two Users.
_Avoid_: User friend, follower, contact

**Friend Presence**:
Whether a Friend currently has at least one authenticated application connection.
_Avoid_: Workspace presence, last seen

**Workspace Role**:
A named permission level held by a workspace member.
_Avoid_: Global role

**Conversation**:
A durable message timeline presented as either a Workspace Channel or a Direct Conversation.
_Avoid_: Thread, chatroom

**Channel**:
A named conversation space inside a workspace.
_Avoid_: Room

**Voice Channel**:
A durable, named audio space inside a Workspace. A Voice Channel is not a
Conversation and does not contain Messages.
_Avoid_: Voice Conversation, Voice Room

**Voice Session**:
An active browser audio connection by one User inside one Voice Channel.
_Avoid_: Participant, membership

**Voice Session ID**:
An opaque runtime identifier for one admitted Voice Session. It is neither a
process identifier nor a Signaling Session ID.
_Avoid_: Session PID, connection ID

**Signaling Session ID**:
An opaque, server-generated identifier that binds signaling messages to one admitted Voice Channel connection. It is not a Voice Session.
_Avoid_: Voice Session ID, socket ID, process ID

**Voice Owner Tab**:
The browser tab that owns a User's active Voice Session and continues playing
voice audio while that tab remains connected.
_Avoid_: Voice browser, active tab

**Audio Route**:
The room-local, directed permission for accepted inbound RTP from one Voice
Session to be delivered to another Voice Session's outbound track.
_Avoid_: RTP route, forwarding edge, media pipe

**Audio Source**:
A Voice Session whose accepted inbound audio track supplies RTP to an Audio
Route.
_Avoid_: Sender, publisher

**Audio Destination**:
A Voice Session whose outbound audio track receives RTP through an Audio Route.
_Avoid_: Receiver, subscriber

**Audio Output Slot**:
A room-local receiving position on a Voice Session for one other Voice Session's
Audio Source. A Voice Session has at most four Audio Output Slots in the capped
Voice Channel; a slot is not itself an Audio Route or a Voice Session.
_Avoid_: Outbound track, remote track

**Direct Conversation**:
A private conversation between exactly two Friends that does not belong to a Workspace.
_Avoid_: DM Channel, private Channel, private chat

**Message**:
A durable item sent by a User within a Conversation.
_Avoid_: Post, chat entry

**Direct Message**:
A Message sent within a Direct Conversation.
_Avoid_: Private message, Workspace message

**Message Reply**:
A Message that references exactly one earlier Message in the same Conversation
and remains part of its normal timeline.
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
A User's global collection of relevant activity across their Workspaces and
Direct Conversations.
_Avoid_: Workspace activity, Activity Page

**Activity Item**:
A durable entry in a User's Activity Feed that links to the relevant Message
or Friend relationship and records whether the User has read it.
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
A User's per-Conversation read position and cached unread summary,
including unread count and first/last unread message sequence bounds.
_Avoid_: Read receipt

**Unread Span**:
An inclusive `{from_seq, to_seq}` interval of unread message sequences for one
User and Conversation.
_Avoid_: Unread range

## Relationships

- A **User** may own many **Workspaces**
- Hard deletion of a **User** is not supported while Direct Conversation identity depends on that User
- A future account-removal workflow must deactivate or anonymize the **User** while preserving durable identity
- A **User** may send a **Friend Request** to another **User**
- A **User** may target a **Friend Request** using another User's exact global username without sharing a **Workspace**
- Users cannot browse or fuzzy-search a global User directory
- A **Friend Request** becomes a **Friendship** only when the receiving User accepts it
- Sending a **Friend Request** to a User who already sent one in the opposite direction accepts the existing request
- A **Friendship** is mutual rather than directional
- Between the same two Users, at most one **Friend Request** or **Friendship** may exist
- Blocking Users is not part of the Friendship model
- **Friend Presence** is either online or offline; idle, invisible, custom status, and last-seen history are not supported
- **Friend Presence** is visible only to current Friends and is not persisted
- Two Friends may have one **Direct Conversation**
- A **Direct Conversation** may be created only between Users who have an accepted **Friendship**
- Accepting a **Friend Request** does not create a **Direct Conversation**
- A **Direct Conversation** is created lazily when either Friend first chooses to message the other
- A **Direct Conversation** contains **Direct Messages**
- A **Direct Conversation** does not belong to a **Workspace**
- The **Direct Messages** area is a User-level destination rather than a special **Workspace**
- The **Direct Messages** area brings together Friends, Friend Requests, and Direct Conversations
- A **Direct Conversation** always has exactly two Users; group direct conversations are not part of the domain
- Users who need a group conversation create or use a **Workspace** and its **Channels**
- Ending a **Friendship** preserves its **Direct Conversation** and message history for both Users
- Users who are no longer Friends may read their existing **Direct Conversation** but may not send new **Direct Messages**
- Users who are no longer Friends may delete their own **Direct Messages** and remove their own existing reactions
- Users who are no longer Friends may not reply, add reactions, or broadcast typing in their **Direct Conversation**
- Restoring a **Friendship** re-enables its existing **Direct Conversation** rather than creating another one
- An open **Direct Conversation** remains visible and changes immediately between writable and read-only modes as its **Friendship** changes
- Every created **Direct Conversation** remains in both Users' Direct Messages list, including empty and read-only Conversations
- Direct Conversations are ordered by their latest Message activity, with empty Conversations ordered by creation time
- Direct Conversations cannot initially be hidden, pinned, closed, or manually reordered
- A User may delete their own **Direct Message**, but not the other participant's **Direct Message**
- Deleting a **Direct Message** replaces it with a deleted-message placeholder for both Users
- A User may still delete their own **Direct Message** after the **Friendship** ends
- Direct Messages cannot be hidden or deleted for only one participant
- A **Workspace Identifier** points to one **Workspace**
- A **Workspace** has zero or more **Workspace Members**
- A **Workspace Member** has one **Workspace Role**
- A **Workspace** contains one or more **Channels** when created through the
  public workspace workflow
- A **Channel** and a **Direct Conversation** are each a **Conversation**
- A **Workspace** may contain **Voice Channels**
- A **Voice Channel** belongs to one **Workspace**
- A **Voice Channel** is not a **Conversation**
- A **Voice Channel** does not contain **Messages**
- Workspace Owners and Admins may create **Voice Channels**
- Workspace Owners and Admins may rename **Voice Channels**
- Workspace Members may view **Voice Channels** in their **Workspace**
- Only a Workspace Owner may delete a **Voice Channel**
- A **Voice Channel** name is unique among a Workspace's Voice Channels, but may
  match a Channel name in that Workspace
- A **Voice Session** belongs to one **Voice Channel**
- A **Voice Session** is runtime state, not durable membership
- A **Voice Session** represents one browser audio connection
- A **Voice Session ID** identifies one **Voice Session** without exposing its
  runtime process
- A User may have at most one active **Voice Session** across the app
- When a User joins a different Voice Channel, the new join moves them by
  ending their existing **Voice Session** before admitting the new one
- A User's **Voice Session** ends when they lose access to its **Voice Channel**
  or that **Voice Channel** is deleted
- A **Voice Session** is controlled by one **Voice Owner Tab**
- A User may continue using the app from other browser tabs while one
  **Voice Owner Tab** remains connected to voice
- A **Voice Session** has at most four **Audio Output Slots** in a Voice
  Channel capped at five active Voice Sessions
- A Voice join requires four usable **Audio Output Slots**; if the Voice Owner
  Tab cannot provide them, the join fails with a retryable compatibility error
  and leaves no partial **Voice Session**
- The Voice Owner Tab checks its four slots before admission, and the Voice
  runtime validates the same requirement from the received offer
- A compatibility failure cleans up the attempted Voice connection and waits
  for an explicit User retry rather than retrying automatically
- A Voice Session that leaves during negotiation ends immediately; later
  signaling or audio for that Session is ignored
- Ending one Voice Session removes only the Audio Routes involving it; the
  remaining Voice Sessions continue exchanging audio when their routes are
  otherwise eligible
- An **Audio Output Slot** stays assigned to its Audio Source while both remain
  active; when that source leaves, only its slot is released for a later source
- An unused **Audio Output Slot** remains available and silent until another
  Audio Source is assigned to it
- An **Audio Output Slot** carries at most one Audio Source at a time and may
  later carry a different source after the first source leaves
- The four **Audio Output Slots** have fixed positions for the life of a Voice
  Session; later source changes do not change the slot positions
- An **Audio Route** connects one **Audio Source** to one **Audio Destination**
  through one destination **Audio Output Slot**
- An eligible **Audio Route** may start while another active Voice Session is
  still connecting; that Session does not block ready source/destination pairs
- A **Conversation** contains **Messages**
- A **Message Reply** references a **Message** in the same **Conversation**
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
- A User's **Activity Feed** includes each **Direct Message** they receive
- Receiving a **Friend Request** creates an **Activity Item** for the receiving User
- Accepting a **Friend Request** creates an **Activity Item** for the requesting User
- Declining a **Friend Request** does not create an **Activity Item**
- Viewing a Friend Request **Activity Item** marks the item read without resolving the request
- Cancelling a pending **Friend Request** removes its received-request **Activity Item**
- A User's own messages never create entries in that User's **Activity Feed**
- Opening a Message-backed **Activity Item** navigates to its source **Message**
  in the source **Conversation** and marks that item as read
- Opening a Friend relationship-backed **Activity Item** navigates to the
  relevant Friends or Friend Requests view and marks that item as read
- Opening the **Activity Feed** does not itself mark **Activity Items** as read
- A User may mark every **Activity Item** as read, and the activity bell count
  reflects unread items
- Mention **Activity Item** read state is independent from Channel **Read State**
- A **Direct Message** becomes read after remaining genuinely visible to its recipient for one continuous second
- Reading a **Direct Message** also marks its **Activity Item** read in the same workflow
- Read **Direct Message** Activity Items disappear from the primary unread activity view but remain in Activity history
- Losing Workspace membership permanently removes that Workspace's entries from
  the former member's **Activity Feed**
- Deleting the message referenced by a **Message Reply** preserves the reply and
  replaces its quoted preview with a deleted-message placeholder
- A deleted message cannot become the target of a new **Message Reply**
- Only Workspace Owners and Admins may create **Channels**
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
- A **Read State** belongs to one **User** and one **Conversation**
- A **Read State** summarizes zero or more **Unread Spans**
- An **Unread Span** belongs to one **User** and one **Conversation**

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
