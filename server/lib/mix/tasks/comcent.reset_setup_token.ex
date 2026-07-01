defmodule Mix.Tasks.Comcent.ResetSetupToken do
  @moduledoc """
  Regenerate the first-run setup token.

      mix comcent.reset_setup_token           # only if token has not been consumed
      mix comcent.reset_setup_token --force   # also clears consumed_at / consumed_by_user_id

  In a release (no Mix available), call equivalently:

      bin/comcent eval 'Comcent.InstanceSetup.regenerate_token!(true)'
  """

  use Mix.Task

  @shortdoc "Regenerate the first-run setup token"

  @impl Mix.Task
  def run(args) do
    force? = "--force" in args

    Mix.Task.run("app.start")

    case Comcent.InstanceSetup.regenerate_token!(force?) do
      {:ok, token} ->
        IO.puts("""

        New setup token:
          #{token}

        Visit /setup on this instance to claim the super-admin account.
        """)

      {:error, :already_consumed} ->
        IO.puts(:stderr, """
        Refusing to regenerate: this instance has already been claimed.

        If you really want to allow a new super-admin to claim it (this
        does NOT revoke the existing super-admin), re-run with --force:

          mix comcent.reset_setup_token --force
        """)

        exit({:shutdown, 1})
    end
  end
end
