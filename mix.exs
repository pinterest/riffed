defmodule Rift.Mixfile do
  use Mix.Project

  def project do
    [app: :thrifty,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps,
     compilers: [:thrift | Mix.compilers],
     thrift_files: Mix.Utils.extract_files(["thrift"], [:thrift])
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :thrift]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
        {:thrift, git: "git@github.pinadmin.com:jon/elixir-thrift.git", submodules: true},
        {:meck, github: "eproxus/meck", tag: "0.8.2", override: true},
        {:mock, github: "jjh42/mock"},
    ]
  end
end
