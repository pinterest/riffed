defmodule Riffed.Mixfile do
  use Mix.Project

  def project do
    [app: :riffed,
     name: "Riffed",
     version: "1.0.0",
     elixir: "~> 1.0",
     deps: deps,
     compilers: compilers(Mix.env),
     erlc_paths: ["src", "ext/thrift/lib/erl/src"],
     erlc_include_path: "ext/thrift/lib/erl/include",
     thrift_files: Mix.Utils.extract_files(["thrift"], [:thrift]),
     docs: [output: "doc/generated"],
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test],

     # Hex
     description: description,
     package: package]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:thrift, :exlager]]
  end

  def compilers(:test) do
    [:thrift | Mix.compilers]
  end

  def compilers(_) do
    Mix.compilers
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
        {:thrift, github: "pinterest/elixir-thrift", tag: "1.0.0", submodules: true},
        {:meck, "~> 0.8.2", only: [:test, :dev]},
        {:mock, github: "jjh42/mock", only: [:test, :dev]},
        {:exlager, github: "khia/exlager"},
        {:earmark, "~> 0.1", only: :dev},
        {:ex_doc, "~> 0.8", only: :dev},
        {:excoveralls, github: "parroty/excoveralls", tag: "v0.4.3", override: true, only: :test}
    ]
  end

  defp description do
    """
    Riffed Provides idiomatic Elixir bindings for Apache Thrift
    """
  end

  defp package do
    [files: ["config", "lib", "test", "thrift", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Jon Parise", "Steve Cohen"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/pinterest/riffed"}]
  end
end
