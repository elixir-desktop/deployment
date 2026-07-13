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

    prepare_keychain(name, pass, full_path, mac_tools)

    uid = import_signing_identity(pass)
    if is_binary(uid), do: System.put_env("DEVELOPER_ID", uid)

    allow_codesign_access(name, pass)
    IO.puts(full_path)
  end

  defp prepare_keychain(name, pass, full_path, mac_tools) do
    if File.exists?(full_path) or File.exists?(full_path <> "-db") do
      security(["delete-keychain", name])
    end

    security(["create-keychain", "-p", pass, name])
    System.put_env("MACOS_KEYCHAIN", full_path)

    security(["list-keychains", "-s", name])
    security(["unlock-keychain", "-p", pass, name])
    security(["set-keychain-settings", "-t", "3600", "-u", name])

    for cert <- Desktop.Deployment.Tooling.wildcard(mac_tools, "*.pem") do
      security(["import", cert, "-k", name, "-A"])
    end
  end

  defp import_signing_identity(pass) do
    p12 = System.get_env("MACOS_P12")
    pem = System.get_env("MACOS_PEM")

    cond do
      is_binary(p12) and byte_size(p12) > 0 ->
        import_p12_identity(p12, pass)

      is_binary(pem) and byte_size(pem) > 0 ->
        import_pem_identity(pem, pass)

      true ->
        raise "No MACOS_P12 or MACOS_PEM env var"
    end
  end

  defp import_p12_identity(p12, pass) do
    p12_password = System.get_env("MACOS_PEM_PASSWORD") || pass
    cert_file = "tmp.cert.pem"

    {_, 0} =
      System.cmd("openssl", [
        "pkcs12",
        "-in",
        p12,
        "-passin",
        "pass:#{p12_password}",
        "-nokeys",
        "-out",
        cert_file
      ])

    uids = locate_uid(cert_file) || raise "Could not locate UID in PKCS12"
    maybe_import_p12(p12, p12_password, uids, pass)
  end

  defp import_pem_identity(pem, pass) do
    file = "tmp.pem"
    File.write!(file, pem)
    uids = locate_uid(file) || raise "Could not locate UID in PEM"
    maybe_import_pem(file, uids, pass)
  end

  defp allow_codesign_access(name, pass) do
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
  end

  defp security(args) do
    IO.puts("Running: security #{Enum.join(args, " ")}")
    {_, 0} = System.cmd("security", args)
  end
end
