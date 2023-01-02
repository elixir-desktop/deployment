defmodule Desktop.Deployment.MixProject do
  use Mix.Project

  @version "1.0.0"
  def project do
    [
      app: :desktop_deployment,
      version: @version,
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      # compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:crypto, :eex, :logger]]
  end

  defp aliases do
    [
      lint: [
        "compile",
        "format --check-formatted",
        "credo"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Credo
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:libpe, "~> 1.1"},
      {:poison, "~> 3.0"}
    ]
  end
end
