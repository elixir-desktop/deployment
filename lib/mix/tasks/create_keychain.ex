defmodule Mix.Tasks.Desktop.CreateKeychain do
  use Mix.Task
  @moduledoc false

  @shortdoc "Creates a new keychain."
  def run(_args) do
    name = "macos-build.keychain"
    base = Mix.Project.deps_paths()[:desktop_deployment] || ""
    mac_tools = Path.join(base, "rel/macosx")

    # security(["delete-keychain", name])
    security(["create-keychain", "-p", "actions", name])

    security([
      "import",
      "#{mac_tools}/Apple Worldwide Developer Relations Certification Authority.pem",
      "-k",
      "macos-build.keychain"
    ])

    security(["list-keychains", "-s", name])
    security(["unlock-keychain", "-p", "actions", name])
    security(["set-keychain-settings", "-t", "3600", "-u", name])
    IO.puts(Path.join([System.get_env("HOME"), "Library/Keychains", name]))
  end

  defp security(args) do
    {_, 0} = System.cmd("security", args)
  end
end
