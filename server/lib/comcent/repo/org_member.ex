defmodule Comcent.Repo.OrgMember do
  import Ecto.Query
  alias Comcent.Repo
  alias Comcent.Schemas.{OrgMember, Org, User, QueueMembership}
  alias Phoenix.PubSub
  require Logger

  def is_user_with_email_an_org_member(email, subdomain) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.email == ^email,
        preload: [:user, :org]

    case Repo.one(query) do
      nil -> nil
      org_member -> org_member
    end
  end

  @doc """
  Gets the current presence of a user in an organization.
  """
  def get_current_presence(subdomain, user_id) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain and om.user_id == ^user_id,
        select: om.presence

    Repo.one(query)
  end

  @doc """
  Updates the presence of a user in an organization only if their current presence is "Busy".
  Returns :ok if update succeeds, {:error, reason} otherwise.
  """
  def update_member_presence_if_busy(subdomain, user_id, presence) do
    update_member_presence_if(subdomain, user_id, "Busy", presence)
  end

  @doc """
  Updates the presence of a user in an organization only if their current presence
  matches the expected value.
  """
  def update_member_presence_if(subdomain, user_id, expected_presence, presence) do
    # Create update query with condition on current presence being "Busy"
    update_query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where:
          o.subdomain == ^subdomain and om.user_id == ^user_id and
            om.presence == ^expected_presence,
        update: [set: [presence: ^presence]]

    case Repo.update_all(update_query, []) do
      {0, _} ->
        {:error,
         "OrgMember not found, organization not found, or presence was not #{expected_presence}"}

      {count, _} when count > 0 ->
        # Broadcast the presence change
        PubSub.broadcast(
          Comcent.PubSub,
          "presence:#{subdomain}",
          {:presence_update,
           %{
             user_id: user_id,
             presence: presence,
             previous_presence: expected_presence
           }}
        )

        # Log warning if multiple records were updated (should be rare)
        if count > 1 do
          Logger.warning(
            "Multiple OrgMembers (#{count}) updated for user_id: #{user_id}, subdomain: #{subdomain}"
          )
        end

        :ok
    end
  end

  def update_member_presence_if_wrap_up(subdomain, user_id, presence) do
    update_member_presence_if(subdomain, user_id, "Wrap Up", presence)
  end

  @doc """
  Updates the presence of a user in an organization.
  """
  def update_member_presence(subdomain, user_id, presence) do
    previous_presence = get_current_presence(subdomain, user_id)

    # Create a single update query with joins
    update_query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain and om.user_id == ^user_id,
        update: [set: [presence: ^presence]]

    case Repo.update_all(update_query, []) do
      {0, _} ->
        {:error, "OrgMember not found or organization not found"}

      {count, _} when count > 0 ->
        # Broadcast the presence change
        PubSub.broadcast(
          Comcent.PubSub,
          "presence:#{subdomain}",
          {:presence_update,
           %{
             user_id: user_id,
             presence: presence,
             previous_presence: previous_presence
           }}
        )

        # Log warning if multiple records were updated (should be rare)
        if count > 1 do
          Logger.warning(
            "Multiple OrgMembers (#{count}) updated for user_id: #{user_id}, subdomain: #{subdomain}"
          )
        end

        # Just return :ok without fetching updated data
        :ok
    end
  end

  @doc """
  Forces a member into Logged Out and prevents later registration events from
  restoring a stale previous presence snapshot.
  """
  def force_member_logged_out(subdomain, user_id) do
    alias Comcent.RedisClient

    redis_key = "previous_presence:#{subdomain}:#{user_id}"
    RedisClient.set(redis_key, "Logged Out")
    update_member_presence(subdomain, user_id, "Logged Out")
  end

  @doc """
  Changes a member's presence to "On Call" and stores their previous presence state in Redis.

  ## Parameters
    - subdomain: The organization's subdomain
    - user_id: The user's ID

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def update_member_presence_to_on_call(subdomain, user_id) do
    alias Comcent.RedisClient

    # First, get the current presence
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain and om.user_id == ^user_id,
        select: om.presence

    case Repo.one(query) do
      nil ->
        {:error, "OrgMember not found or organization not found"}

      "On Call" ->
        {:ok, "On Call"}

      current_presence ->
        # Store the current presence in Redis
        redis_key = "previous_presence:#{subdomain}:#{user_id}"
        RedisClient.set(redis_key, current_presence)

        # Update presence to "On Call"
        update_member_presence(subdomain, user_id, "On Call")
        {:ok, "On Call"}
    end
  end

  @doc """
  Reverts a member's presence from "On Call" to their previous state.
  If the previous state was also "On Call", sets it to "Available".

  ## Parameters
    - subdomain: The organization's subdomain
    - username: The username of the user (should be decoded by the caller)

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def revert_member_presence_from_on_call(subdomain, username) do
    alias Comcent.RedisClient

    user_id = get_user_id_by_username_and_subdomain(username, subdomain)

    Logger.info(
      "Reverting member presence from On Call to #{username} for subdomain #{subdomain}"
    )

    # Get the previous presence from Redis
    redis_key = "previous_presence:#{subdomain}:#{user_id}"

    case RedisClient.get(redis_key) do
      {:ok, nil} ->
        # No previous state found, set to "Available"
        update_member_presence(subdomain, user_id, "Available")

      {:ok, "On Call"} ->
        # Previous state was also "On Call", set to "Available"
        update_member_presence(subdomain, user_id, "Available")

      {:ok, previous_presence} ->
        # Revert to the previous presence
        update_member_presence(subdomain, user_id, previous_presence)

      {:error, reason} ->
        Logger.error("Failed to retrieve previous presence state: #{inspect(reason)}")
        # Set to "Available" as fallback
        update_member_presence(subdomain, user_id, "Available")
    end

    # Clean up the Redis key
    RedisClient.del(redis_key)
  end

  @doc """
  Reverts a member's presence from "Logged Out" to their previous state.
  If the previous state was also "Logged Out", sets it to "Available".

  ## Parameters
    - subdomain: The organization's subdomain
    - username: The username of the user (should be decoded by the caller)

  ## Returns
    - :ok on success
    - {:error, reason} on failure
  """
  def revert_member_presence_from_logged_out(subdomain, username) do
    alias Comcent.RedisClient

    user_id = get_user_id_by_username_and_subdomain(username, subdomain)

    Logger.info("Reverting member presence to #{username} for subdomain #{subdomain}")

    current_presence = get_current_presence(subdomain, user_id)

    if current_presence != "Logged Out" do
      :ok
    else
      # Get the previous presence from Redis
      redis_key = "previous_presence:#{subdomain}:#{user_id}"

      case RedisClient.get(redis_key) do
        {:ok, nil} ->
          # A forced Logged Out state, such as max-no-answer ejection, should
          # remain Logged Out until a user explicitly changes presence.
          :ok

        {:ok, "Logged Out"} ->
          :ok

        {:ok, previous_presence} ->
          # Revert to the previous presence
          update_member_presence(subdomain, user_id, previous_presence)

        {:error, reason} ->
          Logger.error("Failed to retrieve previous presence state: #{inspect(reason)}")
          :ok
      end

      # Clean up the Redis key
      RedisClient.del(redis_key)
    end
  end

  def get_member_by_email_and_subdomain(email, subdomain) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain and u.email == ^email,
        preload: [:user, :org]

    Repo.one(query)
  end

  @doc """
  Gets member details by user_id, subdomain, and queue_id, formatted for queue usage.
  Only returns member details if the member belongs to the specified queue.

  Returns a map with the member's details, including the status set to "Available".
  Returns nil if the member doesn't exist or doesn't belong to the specified queue.
  """
  def get_member_by_user_id_and_queue(user_id, subdomain, queue_id) do
    # Build a query to get member details, checking queue membership
    query =
      from m in OrgMember,
        join: o in Org,
        on: m.org_id == o.id,
        join: u in User,
        on: m.user_id == u.id,
        join: qm in QueueMembership,
        on: qm.user_id == m.user_id and qm.org_id == m.org_id,
        where:
          m.user_id == ^user_id and
            o.subdomain == ^subdomain and
            qm.queue_id == ^queue_id,
        select: %{
          user_id: m.user_id,
          username: m.username,
          presence: m.presence,
          extension_number: m.extension_number,
          org_id: m.org_id,
          subdomain: o.subdomain
        }

    Repo.one(query)
  end

  @doc """
  Gets user_id by username and subdomain from org_member.
  Returns the user_id if found, nil otherwise.
  """
  def get_user_id_by_username_and_subdomain(username, subdomain) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain and om.username == ^username,
        select: om.user_id

    Repo.one(query)
  end

  @doc """
  Checks if a user is a member of an organization.
  Returns the org member record if found, nil otherwise.

  ## Parameters
    - user_id: The ID of the user to check
    - subdomain: The subdomain of the organization

  ## Returns
    - OrgMember struct if the user is a member of the organization
    - nil if the user is not a member
  """
  def is_org_member(user_id, subdomain) do
    query =
      from m in OrgMember,
        join: o in Org,
        on: m.org_id == o.id,
        join: u in User,
        on: m.user_id == u.id,
        where:
          m.user_id == ^user_id and
            o.subdomain == ^subdomain,
        select: m

    Repo.one(query)
  end

  def get_presence_counts(subdomain) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: o.subdomain == ^subdomain,
        group_by: om.presence,
        select: {om.presence, count(om.user_id)}

    Repo.all(query)
    |> Enum.into(%{})
  end

  @doc """
  Gets all members of an organization by subdomain.
  Returns a list of members with their user details preloaded.
  """
  def get_all_members(subdomain) do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        join: u in User,
        on: om.user_id == u.id,
        where: o.subdomain == ^subdomain,
        preload: [:user],
        select: om

    Repo.all(query)
  end

  def list_active_members do
    query =
      from om in OrgMember,
        join: o in Org,
        on: om.org_id == o.id,
        where: om.presence != "Logged Out",
        select: %{
          user_id: om.user_id,
          username: om.username,
          presence: om.presence,
          org_id: om.org_id,
          subdomain: o.subdomain
        }

    Repo.all(query)
  end
end
