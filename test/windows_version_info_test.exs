defmodule Desktop.Deployment.WindowsVersionInfoTest do
  use ExUnit.Case, async: true

  alias Desktop.Deployment.Package

  test "host version info uses the long product name" do
    pkg = %Package{
      name: "dDrive",
      name_long: "Diode Collab",
      company: "Diode",
      description: "Diode"
    }

    host = info_map(Package.host_version_info_args(pkg, "v1.22.17", "1.22.17"))
    beam = info_map(Package.windows_version_info_args(pkg, "v1.22.17", "1.22.17"))

    assert host["FileDescription"] == "Diode Collab"
    assert host["ProductName"] == "Diode Collab"
    assert host["CompanyName"] == "Diode"
    assert host["FileVersion"] == "v1.22.17"
    assert host["ProductVersion"] == "1.22.17"
    assert host["LegalCopyright"] == "Diode. All rights reserved."

    assert beam["FileDescription"] == "Diode"
    assert beam["ProductName"] == "dDrive"
  end

  defp info_map(args) do
    args
    |> Enum.chunk_every(3)
    |> Map.new(fn ["--set-info", key, value] -> {key, value} end)
  end
end
