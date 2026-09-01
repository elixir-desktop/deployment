# Verifies packaging-style Pe.Update --set-icon on real OTP PE binaries.
# Usage: mix run scripts/verify_otp_icons.exs

bins =
  System.get_env("BINS")
  |> String.split("|", trim: true)

icon = System.fetch_env!("ICON")
manifest = System.fetch_env!("MANIFEST")
tmpdir = System.fetch_env!("TMPDIR")

Enum.each(bins, fn bin ->
  name = Path.basename(bin)
  tmp = Path.join(tmpdir, name)
  File.cp!(bin, tmp)

  :ok =
    Mix.Tasks.Pe.Update.run([
      "--set-icon",
      icon,
      "--set-manifest",
      manifest,
      "--set-info",
      "ProductName",
      "Diode Collab",
      "--set-info",
      "FileVersion",
      "1.22.8",
      "--set-info",
      "ProductVersion",
      "1.22.8",
      tmp
    ])

  {:ok, pe} = LibPE.parse_file(tmp)
  rsrc = LibPE.get_resources(pe)
  group = LibPE.Icon.get(rsrc)
  checksum_ok = pe.coff_header.checksum == LibPE.update_checksum(pe).coff_header.checksum

  IO.puts("#{name}: group=#{group != nil} checksum=#{checksum_ok} size=#{File.stat!(tmp).size}")

  if group == nil or not checksum_ok do
    System.halt(1)
  end
end)

IO.puts("OK")
