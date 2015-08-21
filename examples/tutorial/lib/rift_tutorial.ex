defmodule RiftTutorial do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(RiftTutorial.Server, []),
      worker(RiftTutorial.Client, []),
      worker(RiftTutorial.Handler, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RiftTutorial.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
