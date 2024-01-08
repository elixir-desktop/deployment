defmodule Mix.Tasks.Desktop.CreateKeychain do
  use Mix.Task
  import Desktop.Deployment.Package.MacOS
  @moduledoc false

  @shortdoc "Creates a new keychain."
  def run(["maybe"]) do
    pem = String.trim(System.get_env("MACOS_PEM") || "")
    if byte_size(pem) == 0 do
      Mix.Shell.IO.info("No MACOS_PEM env var defined, skipping")
    else
      run([])
    end
  end

  def run(_args) do
    name = "macos-build.keychain"
    pass = "actions"
    base = Mix.Project.deps_paths()[:desktop_deployment] || ""
    mac_tools = Path.join(base, "rel/macosx")
    full_path = Path.join([System.get_env("HOME"), "Library/Keychains", name])
    pem = System.get_env("MACOS_PEM") || raise "No MACOS_PEM env var"

    if File.exists?(full_path) or File.exists?(full_path <> "-db") do
      security(["delete-keychain", name])
    end

    security(["create-keychain", "-p", pass, name])
    System.put_env("MACOS_KEYCHAIN", full_path)

    security(["list-keychains", "-s", name])
    # security(["default-keychain", "-s", name])
    security(["unlock-keychain", "-p", pass, name])
    security(["set-keychain-settings", "-t", "3600", "-u", name])

    security([
      "import",
      "#{mac_tools}/Apple Worldwide Developer Relations Certification Authority.pem",
      "-k",
      "macos-build.keychain",
      "-A"
    ])

    file = "tmp.pem"
    File.write!(file, pem)
    uids = locate_uid(file) || raise "Could not locate UID in PEM"
    maybe_import_pem(file, uids)


    # https://stackoverflow.com/questions/39868578/security-codesign-in-sierra-keychain-ignores-access-control-settings-and-ui-p
    # https://github.com/lando/code-sign-action/blob/main/action.yml
    security([
      "set-key-partition-list",
      "-S",
      "apple-tool:,apple:,codesign:",
      "-s",
      "-k",
      pass,
      name
    ])

    IO.puts(full_path)
  end

  defp security(args) do
    IO.puts("Running: security #{Enum.join(args, " ")}")
    {_, 0} = System.cmd("security", args)
  end
end
