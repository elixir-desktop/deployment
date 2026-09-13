exclude = if match?({:unix, :darwin}, :os.type()), do: [], else: [:macos]
ExUnit.start(exclude: exclude)
