defmodule Desktop.Deployment do
  alias Desktop.Deployment.Package
  require Logger
  @moduledoc false

  def prepare_release(%Mix.Release{options: options} = rel) do
    base = Mix.Project.deps_paths()[:desktop_deployment]
    templates = Path.absname("#{base}/rel")

    %Mix.Release{
      rel
      | options:
          Keyword.put(options, :rel_templates_path, templates)
          |> Keyword.put(:quiet, true)
          |> Keyword.put(:package, default_package(nil))
    }
  end

  def generate_installer(%Mix.Release{} = rel) do
    config = Mix.Project.config()

    if Mix.env() != :prod do
      IO.puts("""
        Desktop.Deployment can only build MIX_ENV=prod releases.

        Please use `MIX_ENV=prod mix release` instead.
      """)

      System.halt(1)
    end

    package =
      case config[:package] do
        nil ->
          Logger.warn(
            "There is no package config defined. Using the generic Elixir App descriptions."
          )

          default_package(rel)

        map ->
          struct!(default_package(rel), map)
      end

    package =
      package
      |> Package.copy_extra_files()
      |> Package.create_installer()

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
end
