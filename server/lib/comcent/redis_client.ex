defmodule Comcent.RedisClient do
  @moduledoc """
  A Redis client wrapper around Redix that provides a simplified interface
  for Redis operations used in the application.
  """

  use GenServer
  require Logger

  @doc """
  Starts the Redis client process.
  """
  def start_link(_opts) do
    redis_config = Application.get_env(:comcent, :redis)
    # Override host to use the container name
    # redis_config = Keyword.put(redis_config, :host, "redis")
    GenServer.start_link(__MODULE__, redis_config, name: __MODULE__)
  end

  @impl true
  def init(redis_config) do
    Logger.info("Redis config: #{inspect(redis_config)}")

    case Redix.start_link(redis_config) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        Logger.error("Failed to connect to Redis: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @doc """
  Pushes a value to the right of a Redis list.

  ## Parameters
    - key: The Redis key for the list
    - value: The value to push to the list

  ## Returns
    - {:ok, length} where length is the new length of the list
    - {:error, reason} on failure
  """
  def rpush(key, value) do
    GenServer.call(__MODULE__, {:rpush, key, value})
  end

  @doc """
  Pushes a value to the left of a Redis list.

  ## Parameters
    - key: The Redis key for the list
    - value: The value to push to the list

  ## Returns
    - {:ok, length} where length is the new length of the list
    - {:error, reason} on failure
  """
  def lpush(key, value) do
    GenServer.call(__MODULE__, {:lpush, key, value})
  end

  @doc """
  Gets a value from Redis by key.

  ## Parameters
    - key: The Redis key to retrieve

  ## Returns
    - {:ok, value} where value is the stored value (nil if key doesn't exist)
    - {:error, reason} on failure
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Sets a value in Redis.

  ## Parameters
    - key: The Redis key to set
    - value: The value to store

  ## Returns
    - {:ok, "OK"} on success
    - {:error, reason} on failure
  """
  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  @doc """
  Sets a value in Redis with an expiration timeout.

  ## Parameters
    - key: The Redis key to set
    - value: The value to store
    - ttl: Time-to-live in seconds

  ## Returns
    - {:ok, "OK"} on success
    - {:error, reason} on failure
  """
  def setex(key, value, ttl) do
    GenServer.call(__MODULE__, {:setex, key, value, ttl})
  end

  @doc """
  Gets all keys matching a pattern.

  ## Parameters
    - pattern: The pattern to match keys against (e.g., "user:*")

  ## Returns
    - {:ok, keys} where keys is a list of matching keys
    - {:error, reason} on failure
  """
  def keys(pattern) do
    GenServer.call(__MODULE__, {:keys, pattern})
  end

  @doc """
  Gets the length of a Redis list.

  ## Parameters
    - key: The Redis key for the list

  ## Returns
    - {:ok, length} where length is the length of the list (0 if key doesn't exist)
    - {:error, reason} on failure
  """
  def llen(key) do
    GenServer.call(__MODULE__, {:llen, key})
  end

  @doc """
  Removes and returns the first element of a Redis list.

  ## Parameters
    - key: The Redis key for the list

  ## Returns
    - {:ok, value} where value is the first element of the list (nil if key doesn't exist)
    - {:error, reason} on failure
  """
  def lpop(key) do
    GenServer.call(__MODULE__, {:lpop, key})
  end

  @doc """
  Gets a range of elements from a Redis list.

  ## Parameters
    - key: The Redis key for the list
    - start: Start index (0-based)
    - stop: Stop index (inclusive)

  ## Returns
    - {:ok, values} where values is a list of the retrieved elements
    - {:error, reason} on failure
  """
  def lrange(key, start, stop) do
    GenServer.call(__MODULE__, {:lrange, key, start, stop})
  end

  @doc """
  Acquires a distributed lock in Redis using SET NX EX pattern.

  ## Parameters
    - key: The key to use for the lock
    - identifier: Unique identifier for the lock (usually a UUID)
    - timeout_seconds: Time in seconds after which the lock expires

  ## Returns
    - {:ok, identifier} if lock was acquired successfully
    - {:error, :already_acquired} if lock is already held
    - {:error, reason} on failure
  """
  def acquire_lock(key, identifier, timeout_seconds) do
    GenServer.call(__MODULE__, {:acquire_lock, key, identifier, timeout_seconds})
  end

  @doc """
  Releases a previously acquired lock.

  ## Parameters
    - key: The key used for the lock
    - identifier: The identifier used when acquiring the lock

  ## Returns
    - {:ok, result} where result is the number of keys deleted (1 if successful, 0 if key didn't exist)
    - {:error, reason} on failure
  """
  def release_lock(key, identifier) do
    GenServer.call(__MODULE__, {:release_lock, key, identifier})
  end

  @doc """
  Sets up a listener for expired keys in Redis.

  ## Parameters
    - callback: The function to be called when a key expires

  ## Returns
    - {:ok, pubsub} on success
    - {:error, reason} on failure
  """
  def listen_for_expired_keys(callback) do
    redis_config = Application.get_env(:comcent, :redis)
    # Override host to use the container name
    # redis_config = Keyword.put(redis_config, :host, "redis")

    # First configure Redis to notify on key expiration events using a regular connection
    case Redix.start_link(redis_config) do
      {:ok, conn} ->
        # Configure Redis to notify on key expiration events
        case Redix.command(conn, ["CONFIG", "SET", "notify-keyspace-events", "Ex"]) do
          {:ok, _} ->
            # Now start a PubSub connection for listening to events
            case Redix.PubSub.start_link(redis_config) do
              {:ok, pubsub} ->
                # Subscribe to key expiration events
                Redix.PubSub.subscribe(pubsub, "__keyevent@0__:expired", self())

                # Start a process to handle the messages
                spawn(fn -> handle_expired_keys(pubsub, callback) end)
                Logger.info("Subscribed to __keyevent@0__:expired for key expiration events")
                {:ok, pubsub}

              {:error, reason} ->
                Logger.error("Failed to connect to Redis PubSub: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            Logger.error("Error setting up expiration listener: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to connect to Redis: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_expired_keys(pubsub, callback) do
    receive do
      {:redix_pubsub, ^pubsub, :message, %{channel: "__keyevent@0__:expired", payload: key}} ->
        callback.(key)
        handle_expired_keys(pubsub, callback)
    end
  end

  @doc """
  Increments the integer value of a key by one.

  ## Parameters
    - key: The Redis key to increment

  ## Returns
    - {:ok, new_value} where new_value is the incremented value
    - {:error, reason} on failure
  """
  def incr(key) do
    GenServer.call(__MODULE__, {:incr, key})
  end

  @doc """
  Decrements the integer value of a key by one.

  ## Parameters
    - key: The Redis key to decrement

  ## Returns
    - {:ok, new_value} where new_value is the decremented value
    - {:error, reason} on failure
  """
  def decr(key) do
    GenServer.call(__MODULE__, {:decr, key})
  end

  @doc """
  Gets the element at a specific index in a Redis list.

  ## Parameters
    - key: The Redis key for the list
    - index: The index of the element to retrieve (0-based)

  ## Returns
    - {:ok, value} where value is the element at the specified index (nil if index out of range)
    - {:error, reason} on failure
  """
  def lindex(key, index) do
    GenServer.call(__MODULE__, {:lindex, key, index})
  end

  @doc """
  Sets the value of an element in a Redis list by its index.

  ## Parameters
    - key: The Redis key for the list
    - index: The index of the element to set (0-based)
    - value: The new value to set

  ## Returns
    - {:ok, "OK"} on success
    - {:error, reason} on failure
  """
  def lset(key, index, value) do
    GenServer.call(__MODULE__, {:lset, key, index, value})
  end

  @doc """
  Deletes a key from Redis.
  """
  def del(key) do
    GenServer.call(__MODULE__, {:del, key})
  end

  @impl true
  def handle_call({:rpush, key, value}, _from, conn) do
    case Redix.command(conn, ["RPUSH", key, value]) do
      {:ok, length} -> {:reply, {:ok, length}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:lpush, key, value}, _from, conn) do
    case Redix.command(conn, ["LPUSH", key, value]) do
      {:ok, length} -> {:reply, {:ok, length}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:get, key}, _from, conn) do
    case Redix.command(conn, ["GET", key]) do
      {:ok, value} -> {:reply, {:ok, value}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:set, key, value}, _from, conn) do
    case Redix.command(conn, ["SET", key, value]) do
      {:ok, "OK"} -> {:reply, {:ok, "OK"}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:setex, key, value, ttl}, _from, conn) do
    case Redix.command(conn, ["SET", key, value, "EX", to_string(ttl)]) do
      {:ok, "OK"} -> {:reply, {:ok, "OK"}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:keys, pattern}, _from, conn) do
    case Redix.command(conn, ["KEYS", pattern]) do
      {:ok, keys} -> {:reply, {:ok, keys}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:llen, key}, _from, conn) do
    case Redix.command(conn, ["LLEN", key]) do
      {:ok, length} -> {:reply, {:ok, length}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:lpop, key}, _from, conn) do
    case Redix.command(conn, ["LPOP", key]) do
      {:ok, value} -> {:reply, {:ok, value}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:lrange, key, start, stop}, _from, conn) do
    case Redix.command(conn, ["LRANGE", key, start, stop]) do
      {:ok, values} -> {:reply, {:ok, values}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:acquire_lock, key, identifier, timeout_seconds}, _from, conn) do
    case Redix.command(conn, ["SET", key, identifier, "NX", "EX", to_string(timeout_seconds)]) do
      {:ok, "OK"} ->
        # Lock successfully acquired
        {:reply, {:ok, identifier}, conn}

      {:ok, nil} ->
        # Key already exists, lock not acquired
        {:reply, {:error, :already_acquired}, conn}

      {:error, reason} ->
        {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:release_lock, key, identifier}, _from, conn) do
    # Get the current value first to ensure we're releasing our own lock
    case Redix.command(conn, ["GET", key]) do
      {:ok, ^identifier} ->
        # We own the lock, delete it
        case Redix.command(conn, ["DEL", key]) do
          {:ok, result} -> {:reply, {:ok, result}, conn}
          {:error, reason} -> {:reply, {:error, reason}, conn}
        end

      {:ok, lock_value} ->
        # Someone else owns the lock
        Logger.warning(
          "Lock not released for key: #{key} with identifier: #{identifier} and value: #{lock_value}"
        )

        {:reply, {:error, :not_lock_owner}, conn}

      {:error, reason} ->
        {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:incr, key}, _from, conn) do
    case Redix.command(conn, ["INCR", key]) do
      {:ok, value} -> {:reply, {:ok, value}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:decr, key}, _from, conn) do
    case Redix.command(conn, ["DECR", key]) do
      {:ok, value} -> {:reply, {:ok, value}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:lindex, key, index}, _from, conn) do
    case Redix.command(conn, ["LINDEX", key, index]) do
      {:ok, value} -> {:reply, {:ok, value}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:lset, key, index, value}, _from, conn) do
    case Redix.command(conn, ["LSET", key, index, value]) do
      {:ok, "OK"} -> {:reply, {:ok, "OK"}, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end

  @impl true
  def handle_call({:del, key}, _from, conn) do
    case Redix.command(conn, ["DEL", key]) do
      {:ok, _} -> {:reply, :ok, conn}
      {:error, reason} -> {:reply, {:error, reason}, conn}
    end
  end
end
