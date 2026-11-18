defmodule Desktop.Deployment.WindowsVersionInfoTest do
  use ExUnit.Case, async: true

  alias Desktop.Deployment.Package

  test "host and beam version info share the long product name" do
    pkg = %Package{
      name: "dDrive",
      name_long: "Diode Collab",
      company: "Diode",
      description: "Diode",
      identifier: "io.diode.ddrive"
    }

    host = info_map(Package.host_version_info_args(pkg, "v1.22.17", "1.22.17"))
    beam = info_map(Package.windows_version_info_args(pkg, "v1.22.17", "1.22.17"))

    assert host["FileDescription"] == "Diode Collab"
    assert host["ProductName"] == "Diode Collab"
    assert host["CompanyName"] == "Diode"
    assert host["FileVersion"] == "v1.22.17"
    assert host["ProductVersion"] == "1.22.17"
    assert host["LegalCopyright"] == "Diode. All rights reserved."

    assert beam["FileDescription"] == "Diode Collab"
    assert beam["ProductName"] == "Diode Collab"
    assert beam == host
  end

  test "host ini embeds package.identifier as app_user_model_id" do
    body =
      Desktop.Deployment.Package.Windows.host_ini_content("beam", "ddrive.bat", "io.diode.ddrive")

    assert body =~ "[windows]"
    assert body =~ "app_user_model_id = io.diode.ddrive"
    assert body =~ "app_name = ddrive.bat"
    refute body =~ "[ui]"
  end

  test "host ini embeds splash_icon when provided" do
    body =
      Desktop.Deployment.Package.Windows.host_ini_content(
        "beam",
        "ddrive.bat",
        "io.diode.ddrive",
        "splash.png"
      )

    assert body =~ "[ui]"
    assert body =~ "splash_icon = splash.png"
  end

  test "nsis template stamps APP_USER_MODEL_ID from package.identifier" do
    nsi = File.read!(Package.toolpath("rel/win32/app.nsi.eex"))
    assert nsi =~ ~s(!define APP_USER_MODEL_ID "<%= @package.identifier %>")
    assert nsi =~ "SetLnkAppUserModelId"
    assert File.exists?(Package.toolpath("rel/win32/aumid.nsh"))
  end

  defp info_map(args) do
    args
    |> Enum.chunk_every(3)
    |> Map.new(fn ["--set-info", key, value] -> {key, value} end)
  end
end
