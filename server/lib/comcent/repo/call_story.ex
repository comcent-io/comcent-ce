defmodule Comcent.Repo.CallStory do
  import Ecto.Query
  require Logger
  alias Comcent.Repo
  alias Comcent.Schemas.{CallStory, Org, CallSearchVector}

  def list_call_stories(subdomain, items_per_page, current_page, nil, nil) do
    from(cs in CallStory,
      join: o in Org,
      on: cs.org_id == o.id,
      where: o.subdomain == ^subdomain
    )
    |> preload([:call_spans, :call_story_events])
    |> limit(^items_per_page)
    |> offset(^((current_page - 1) * items_per_page))
    |> order_by(desc: :start_at)
    |> Repo.all()
  end

  def list_call_stories(subdomain, items_per_page, current_page, search_text, nil) do
    with {:ok, embedding} <- Comcent.OpenAI.embed_text(search_text) do
      from(cs in CallStory,
        join: o in Org,
        on: cs.org_id == o.id,
        where: o.subdomain == ^subdomain,
        join: csv in CallSearchVector,
        on: cs.id == csv.call_story_id,
        order_by: fragment("embeddings <-> ?", ^embedding),
        limit: ^items_per_page,
        offset: ^((current_page - 1) * items_per_page)
      )
      |> preload([:call_spans, :call_story_events])
      |> Repo.all()
    end
  end

  def list_call_stories(subdomain, items_per_page, current_page, nil, labels)
      when is_list(labels) and length(labels) > 0 do
    Logger.info("Filtering by labels: #{inspect(labels)}")

    from(cs in CallStory,
      join: o in Org,
      on: cs.org_id == o.id,
      where: o.subdomain == ^subdomain,
      where: fragment("? \\?| ?::text[]", cs.labels, type(^labels, {:array, :string}))
    )
    |> preload([:call_spans, :call_story_events])
    |> limit(^items_per_page)
    |> offset(^((current_page - 1) * items_per_page))
    |> order_by(desc: :start_at)
    |> Repo.all()
  end

  def list_call_stories(subdomain, items_per_page, current_page, search_text, labels)
      when is_list(labels) and length(labels) > 0 do
    # Combine semantic search with label filtering using ?| operator for GIN index
    Logger.info("Filtering by labels: #{inspect(labels)}")

    with {:ok, embedding} <- Comcent.OpenAI.embed_text(search_text) do
      from(cs in CallStory,
        join: o in Org,
        on: cs.org_id == o.id,
        where: o.subdomain == ^subdomain,
        where: fragment("? \\?| ?::text[]", cs.labels, type(^labels, {:array, :string})),
        join: csv in CallSearchVector,
        on: cs.id == csv.call_story_id,
        order_by: fragment("embeddings <-> ?", ^embedding),
        limit: ^items_per_page,
        offset: ^((current_page - 1) * items_per_page)
      )
      |> preload([:call_spans, :call_story_events])
      |> Repo.all()
    end
  end

  # Fallback: Handle invalid labels (string, empty list, etc.) - treat as no labels
  def list_call_stories(subdomain, items_per_page, current_page, nil, _labels) do
    # If labels is not a valid non-empty list, treat as no labels filter
    list_call_stories(subdomain, items_per_page, current_page, nil, nil)
  end

  def list_call_stories(subdomain, items_per_page, current_page, search_text, _labels) do
    # If labels is not a valid non-empty list, treat as search only
    list_call_stories(subdomain, items_per_page, current_page, search_text, nil)
  end

  def get_call_stories_count(subdomain) do
    base_query =
      from cs in CallStory,
        join: o in Org,
        on: cs.org_id == o.id,
        where: o.subdomain == ^subdomain

    Repo.aggregate(base_query, :count, :id)
  end

  def fetch_call_stories_with_id(subdomain, customer_number) do
    query =
      from cs in CallStory,
        join: o in Org,
        on: cs.org_id == o.id,
        where:
          o.subdomain == ^subdomain and
            ((cs.direction == "inbound" and
                fragment("? LIKE ?", cs.caller, ^"%#{customer_number}%")) or
               (cs.direction == "outbound" and
                  fragment("? LIKE ?", cs.callee, ^"%#{customer_number}%"))),
        select: %{id: cs.id}

    Repo.all(query)
  end

  def get_call_story_association(call_story_id) do
    query =
      from cs in CallStory,
        where: cs.id == ^call_story_id,
        preload: [
          :call_spans,
          :call_story_events,
          org: [:webhooks]
        ]

    Repo.one(query)
  end

  def get_call_stories_association(call_story_ids) when is_binary(call_story_ids) do
    get_call_stories_association([call_story_ids])
  end

  def get_call_stories_association(call_story_ids) when is_list(call_story_ids) do
    query =
      from cs in CallStory,
        where: cs.id in ^call_story_ids,
        preload: [
          :call_spans,
          :call_story_events,
          org: [:webhooks]
        ]

    Repo.all(query)
  end
end
