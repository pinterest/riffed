defmodule Riffed.Mixfile do
  use Mix.Project

  def project do
    [app: :riffed,
     name: "Riffed",
     version: "1.0.0",
     elixir: "~> 1.2",
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
     package: package,
     source_url: project_url,
     homepage_url: project_url
    ]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [applications: [:logger, :thrift]]
  end

  def compilers(:test) do
    [:thrift | Mix.compilers]
  end

  def compilers(_) do
    Mix.compilers
  end

  defp deps do
    [
        {:thrift, "~> 1.3"},
        {:meck, "~> 0.8.2", only: [:test, :dev]},
        {:mock, github: "jjh42/mock", only: [:test, :dev]},
        {:earmark, "~> 0.1", only: :dev},
        {:ex_doc, "~> 0.8", only: :dev},
        {:excoveralls, github: "parroty/excoveralls", tag: "v0.4.5", override: true, only: :test}
    ]
  end

  defp description do
    """
    Riffed Provides idiomatic Elixir bindings for Apache Thrift
    """
  end

  defp project_url do
     """
     https://github.com/pinterest/riffed
     """
  end

  defp package do
    [files: ["config", "lib", "test", "thrift", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Jon Parise", "Steve Cohen"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => project_url}
    ]
  end
end
