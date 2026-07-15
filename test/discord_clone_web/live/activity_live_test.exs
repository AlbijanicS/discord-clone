defmodule DiscordCloneWeb.ActivityLiveTest do
  use DiscordCloneWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import DiscordCloneWeb.WorkspaceLiveTestHelpers, only: [add_workspace_member!: 2]

  alias DiscordClone.Activities.ActivityItem
  alias DiscordClone.Chat
  alias DiscordClone.Repo
  alias DiscordClone.Workspaces

  describe "authenticated Activity Feed" do
    test "redirects unauthenticated users to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/activity")
    end

    test "renders the stable empty feed and linked global bell", %{conn: conn} do
      recipient = DiscordClone.AccountsFixtures.user_fixture()
      recipient_conn = log_in_user(conn, recipient)

      {:ok, view, _html} = live(recipient_conn, ~p"/activity")

      assert has_element?(view, "#global-activity-bell[href='/activity']")
      assert has_element?(view, "#activity-feed")
      assert has_element?(view, "#activity-feed-empty-state")
      refute has_element?(view, "#activity-feed > article")
    end

    test "shows only the user's feed with current labels and previews newest first", %{
      conn: conn
    } do
      recipient_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      recipient_conn = log_in_user(conn, recipient_scope.user)
      other_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      first_author_scope = DiscordClone.AccountsFixtures.user_scope_fixture()
      second_author_scope = DiscordClone.AccountsFixtures.user_scope_fixture()

      {:ok, first_workspace} =
        Workspaces.create_workspace(first_author_scope, %{name: "Old First Name"})

      {:ok, second_workspace} =
        Workspaces.create_workspace(second_author_scope, %{name: "Second Workspace"})

      add_workspace_member!(first_workspace, recipient_scope)
      add_workspace_member!(first_workspace, other_scope)
      add_workspace_member!(second_workspace, recipient_scope)

      assert {:ok, first_message} =
               Chat.send_message(first_author_scope, first_workspace.default_channel_id, %{
                 content: "older source preview @#{recipient_scope.user.username}"
               })

      assert {:ok, second_message} =
               Chat.send_message(second_author_scope, second_workspace.default_channel_id, %{
                 content: "newer source preview @#{recipient_scope.user.username}"
               })

      assert {:ok, other_message} =
               Chat.send_message(first_author_scope, first_workspace.default_channel_id, %{
                 content: "other user's private preview @#{other_scope.user.username}"
               })

      first_item = activity_item_for_message!(first_message.id)
      second_item = activity_item_for_message!(second_message.id)
      other_item = activity_item_for_message!(other_message.id)

      set_activity_time!(first_item, ~U[2026-07-15 09:00:00.000000Z])
      set_activity_time!(second_item, ~U[2026-07-15 10:00:00.000000Z])

      assert {:ok, _renamed_workspace} =
               Workspaces.rename_workspace(first_author_scope, first_workspace.id, %{
                 name: "Current First Name"
               })

      assert {:ok, _renamed_channel} =
               Workspaces.rename_channel(
                 first_author_scope,
                 first_workspace.id,
                 first_workspace.default_channel_id,
                 %{name: "current-channel"}
               )

      Repo.update_all(
        from(activity_item in ActivityItem, where: activity_item.id == ^first_item.id),
        set: [actor_user_id: nil]
      )

      {:ok, view, _html} = live(recipient_conn, ~p"/activity")

      assert activity_row_ids(view) == [
               "activity-item-#{second_item.id}",
               "activity-item-#{first_item.id}"
             ]

      assert has_element?(
               view,
               "#activity-item-#{first_item.id} [data-role='workspace']",
               "Current First Name"
             )

      assert has_element?(
               view,
               "#activity-item-#{first_item.id} [data-role='channel']",
               "#current-channel"
             )

      assert has_element?(
               view,
               "#activity-item-#{first_item.id} [data-role='actor']",
               "Former member"
             )

      assert has_element?(
               view,
               "#activity-item-#{second_item.id} [data-role='actor']",
               second_author_scope.user.username
             )

      assert has_element?(
               view,
               "#activity-item-#{first_item.id} [data-role='kind']",
               "Direct mention"
             )

      assert has_element?(
               view,
               "#activity-item-#{first_item.id} [data-role='preview']",
               first_message.content
             )

      assert has_element?(
               view,
               "#activity-item-#{second_item.id} [data-role='preview']",
               second_message.content
             )

      refute has_element?(view, "#activity-item-#{other_item.id}")
      assert {:ok, 2} = Chat.unread_activity_count(recipient_scope)
      assert is_nil(Repo.get!(ActivityItem, first_item.id).read_at)
      assert is_nil(Repo.get!(ActivityItem, second_item.id).read_at)
    end
  end

  defp activity_item_for_message!(message_id) do
    Repo.get_by!(ActivityItem, source_message_id: message_id)
  end

  defp set_activity_time!(activity_item, inserted_at) do
    activity_item
    |> Ecto.Changeset.change(inserted_at: inserted_at)
    |> Repo.update!()
  end

  defp activity_row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> then(& &1["#activity-feed > article"])
    |> LazyHTML.attribute("id")
  end
end
