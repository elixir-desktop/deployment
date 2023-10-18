defmodule Desktop.MacOS do
  import Desktop.Deployment.Tooling

  @uid_attribute {0, 9, 2342, 19_200_300, 100, 1, 1}
  def locate_uid(pem_filename) do
    cert = File.read!(pem_filename)
    cert_der = List.keyfind!(:public_key.pem_decode(cert), :Certificate, 0)

    :public_key.der_decode(:Certificate, elem(cert_der, 1))
    |> scan()
  end

  def find_developer_id() do
    cond do
      System.get_env("DEVELOPER_ID") != nil ->
        System.get_env("DEVELOPER_ID")

      System.get_env("MACOS_DEVELOPER_ID") != nil ->
        System.get_env("MACOS_DEVELOPER_ID")

      System.get_env("MACOS_PEM") != nil ->
        file = "tmp.pem"
        File.write!(file, System.get_env("MACOS_PEM"))
        cmd!("security", ["import", file])
        locate_uid(file)
    end
  end

  defp scan({:AttributeTypeAndValue, @uid_attribute, uid}) do
    String.trim(uid)
  end

  defp scan([head | tail]), do: scan(head) || scan(tail)
  defp scan(tuple) when is_tuple(tuple), do: scan(Tuple.to_list(tuple))
  defp scan(_), do: nil

  # openssl genrsa -out mock.key 2048
  # openssl req -new -config ./Developer_ID_mock.conf -key mock.key -out mock.csr
  # openssl req -x509 -days 1825 -key mock.key -in mock.csr -out mock.crt -copy_extensions copy
  # cat mock.crt mock.key > mock.pem
  # openssl pkcs12 -inkey mock.key -in mock.crt -export -out mock.pfx
end
