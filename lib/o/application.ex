defmodule O.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    to_create = %{
      "VM.Standard.A1.Flex" => ["alice", "bob", "chad"],
      "VM.Standard.E2.1.Micro" => ["ivan"]
    }

    loopers =
      Enum.map(to_create, fn {shape, names} ->
        %{
          id: shape,
          start: {GenServer, :start_link, [O, %{names: names, shape: shape}]},
          restart: :transient
        }
      end)

    children = [
      {Finch, name: O.finch()},
      %{
        id: :loopers,
        type: :supervisor,
        start: {Supervisor, :start_link, [loopers, [strategy: :one_for_one, name: :loopers]]}
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: O.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
