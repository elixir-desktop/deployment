defmodule LocateUidTest do
  use ExUnit.Case

  alias Desktop.Deployment.Package.MacOS

  test "locate_uid/1 can decode a PEM after ensuring :public_key is available" do
    dir = System.tmp_dir!()
    key = Path.join(dir, "desktop-deployment-test-key.pem")
    cert = Path.join(dir, "desktop-deployment-test-cert.pem")

    try do
      {_, 0} =
        System.cmd("openssl", [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-keyout",
          key,
          "-out",
          cert,
          "-days",
          "1",
          "-nodes",
          "-subj",
          "/CN=Desktop Deployment Test (TESTUID)"
        ])

      # Must not raise UndefinedFunctionError for :public_key.pem_decode/1
      uids = MacOS.locate_uid(cert)
      assert is_list(uids)
      assert "TESTUID" in uids
    after
      File.rm(key)
      File.rm(cert)
    end
  end
end
