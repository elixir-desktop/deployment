defmodule Desktop.Deployment do
  alias Desktop.Deployment.Package
  require Logger
  @moduledoc false

  def package(rel \\ nil) do
    config = Mix.Project.config()

    cond do
      config[:package] != nil ->
        config[:package] |> expand_package_opts() |> then(&struct!(default_package(rel), &1))

      config[:desktop_package] != nil ->
        config[:desktop_package]
        |> expand_package_opts()
        |> then(&struct!(default_package(rel), &1))

      true ->
        Logger.warning(
          "There is no package config defined. Using the generic Elixir App descriptions."
        )

        default_package(rel)
    end
  end

  # Map deprecated package keys onto layout/host fields so apps never need
  # deployment to know about a particular webview OTP application.
  defp expand_package_opts(opts) when is_list(opts) do
    opts = Map.new(opts)

    layout =
      case Map.fetch(opts, :macos_layout) do
        {:ok, layout} ->
          layout

        :error ->
          case Map.get(opts, :webview_backend) do
            :wx -> :release_first
            :desktop_webview -> :host_first
            _ -> :host_first
          end
      end

    host_binary = Map.get(opts, :host_binary) || Map.get(opts, :webview_binary)

    opts
    |> Map.drop([:webview_backend, :webview_binary])
    |> Map.put(:macos_layout, layout)
    |> Map.put(:host_binary, host_binary)
    |> Map.to_list()
  end

  def generate_installer(%Mix.Release{} = rel) do
    if Mix.env() != :prod do
      IO.puts("""
        Desktop.Deployment can only build MIX_ENV=prod releases.

        Please use `MIX_ENV=prod mix release` instead.
      """)

      System.halt(1)
    end

    package =
      prepare_release(rel)
      |> package()
      |> Package.copy_extra_files()
      |> Package.create_installer()

    IO.puts("")
    IO.puts("Thanks for using elixir-desktop")

    case package do
      %{priv: %{installer_name: installer_name}} ->
        IO.puts("Installer created at #{installer_name}")

      %{} ->
        IO.puts("No installer created")
    end

    package.release
  end

  def default_package(rel) do
    app_name = Mix.Project.config()[:app]

    name =
      app_name
      |> Atom.to_string()
      |> Macro.camelize()

    %Package{
      name: name,
      name_long: "The #{name}",
      description: "#{name} is an Elixir App for Desktop",
      description_long: "#{name} for Desktop is powered by Phoenix LiveView",
      icon: "priv/icon.png",
      # https://developer.gnome.org/menu-spec/#additional-category-registry
      category_gnome: "GNOME;GTK;Office;",
      category_macos: "public.app-category.productivity",
      identifier: "io.#{String.downcase(name)}.app",
      # defined during the process
      app_name: app_name,
      release: rel
    }
  end

  defp prepare_release(%Mix.Release{options: options} = rel) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    templates = Path.absname("#{base}/rel")

    %Mix.Release{
      rel
      | options:
          Keyword.put(options, :rel_templates_path, templates)
          |> Keyword.put(:quiet, true)
    }
  end
end
