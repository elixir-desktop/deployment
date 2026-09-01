defmodule Desktop.Deployment.PeUpdateTest do
  use ExUnit.Case, async: false

  alias LibPE.ResourceTable
  alias LibPE.ResourceTable.{DataBlob, DirEntry}

  @fixtures Path.join([Mix.Project.deps_path(), "libpe", "test", "fixtures"])
  @hello Path.join([@fixtures, "base", "hello.exe"])
  @logo Path.join([@fixtures, "logo.ico"])

  @manifest """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
    <assemblyIdentity version="1.0.0.0" name="Test.app"/>
  </assembly>
  """

  @tag :windows_pe
  test "packaging Pe.Update args embed icon, manifest, version, checksum" do
    unless File.exists?(@hello) and File.exists?(@logo) do
      flunk("libpe fixtures missing at #{@fixtures} (run mix deps.get)")
    end

    tmp = Path.join(System.tmp_dir!(), "dep_pe_#{System.unique_integer([:positive])}.exe")

    manifest =
      Path.join(System.tmp_dir!(), "dep_manifest_#{System.unique_integer([:positive])}.xml")

    File.cp!(@hello, tmp)
    File.write!(manifest, @manifest)

    on_exit(fn ->
      File.rm(tmp)
      File.rm(manifest)
    end)

    # Same shape as package.ex host-first path (no subsystem change)
    args = [
      "--set-icon",
      @logo,
      "--set-manifest",
      manifest,
      "--set-info",
      "CompanyName",
      "TestCo",
      "--set-info",
      "ProductName",
      "TestApp",
      "--set-info",
      "FileVersion",
      "1.0.0",
      "--set-info",
      "ProductVersion",
      "1.0.0",
      tmp
    ]

    :ok = Mix.Tasks.Pe.Update.run(args)

    {:ok, pe} = LibPE.parse_file(tmp)
    rsrc = LibPE.get_resources(pe)

    assert find_type(rsrc, "RT_GROUP_ICON")
    assert find_type(rsrc, "RT_ICON")
    assert find_type(rsrc, "RT_MANIFEST")
    assert find_type(rsrc, "RT_VERSION")
    assert LibPE.Icon.get(rsrc)
    assert pe.coff_header.checksum == LibPE.update_checksum(pe).coff_header.checksum

    icons = icon_payloads(rsrc)
    assert length(icons) >= 1
    refute Enum.any?(icons, fn data -> binary_part(data, 0, 4) == <<0, 0, 1, 0>> end)
  end

  defp icon_payloads(rsrc) do
    case find_type(rsrc, "RT_ICON") do
      %DirEntry{entry: %ResourceTable{entries: names}} ->
        Enum.map(names, fn %DirEntry{entry: %ResourceTable{entries: langs}} ->
          %DirEntry{entry: %DataBlob{data: data}} = hd(langs)
          data
        end)

      _ ->
        []
    end
  end

  defp find_type(%ResourceTable{entries: entries}, type_name) do
    type = LibPE.ResourceTypes.encode(type_name)
    Enum.find(entries, fn %DirEntry{name: n} -> n == type end)
  end
end
