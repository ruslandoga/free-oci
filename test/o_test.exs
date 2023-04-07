defmodule OTest do
  use ExUnit.Case

  setup do
    # https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures-08#appendix-C
    put_test_env(
      key_id: "Test",
      private_key: """
      -----BEGIN RSA PRIVATE KEY-----
      MIICXgIBAAKBgQDCFENGw33yGihy92pDjZQhl0C36rPJj+CvfSC8+q28hxA161QF
      NUd13wuCTUcq0Qd2qsBe/2hFyc2DCJJg0h1L78+6Z4UMR7EOcpfdUE9Hf3m/hs+F
      UR45uBJeDK1HSFHD8bHKD6kv8FPGfJTotc+2xjJwoYi+1hqp1fIekaxsyQIDAQAB
      AoGBAJR8ZkCUvx5kzv+utdl7T5MnordT1TvoXXJGXK7ZZ+UuvMNUCdN2QPc4sBiA
      QWvLw1cSKt5DsKZ8UETpYPy8pPYnnDEz2dDYiaew9+xEpubyeW2oH4Zx71wqBtOK
      kqwrXa/pzdpiucRRjk6vE6YY7EBBs/g7uanVpGibOVAEsqH1AkEA7DkjVH28WDUg
      f1nqvfn2Kj6CT7nIcE3jGJsZZ7zlZmBmHFDONMLUrXR/Zm3pR5m0tCmBqa5RK95u
      412jt1dPIwJBANJT3v8pnkth48bQo/fKel6uEYyboRtA5/uHuHkZ6FQF7OUkGogc
      mSJluOdc5t6hI1VsLn0QZEjQZMEOWr+wKSMCQQCC4kXJEsHAve77oP6HtG/IiEn7
      kpyUXRNvFsDE0czpJJBvL/aRFUJxuRK91jhjC68sA7NsKMGg5OXb5I5Jj36xAkEA
      gIT7aFOYBFwGgQAQkWNKLvySgKbAZRTeLBacpHMuQdl1DfdntvAyqpAZ0lY0RKmW
      G6aFKaqQfOXKCyWoUiVknQJAXrlgySFci/2ueKlIE1QqIiLSZ8V8OlpFLRnb1pzI
      7U1yQXnTAEFYM560yJlzUpOb1V4cScGd365tiSMvxLOvTA==
      -----END RSA PRIVATE KEY-----\
      """
    )
  end

  test "signature" do
    assert O.authorization([{"date", "Thu, 05 Jan 2014 21:31:40 GMT"}]) ==
             """
             Signature version="1",keyId="Test",algorithm="rsa-sha256",headers="date",\
             signature="jKyvPcxB4JbmYY4mByyBY7cZfNl4OW9HpFQlG7N4YcJPteKTu4MWCLyk+gIr0wDgqtLWf9NLpMAMimdfsH7FSWGfbMFSrsVTHNTk0rK3usrfFnti1dxsM4jl0kYJCKTGI/UWkqiaxwNiKqGcdlEDrTcUhhsFsOIo8VhddmZTZ8w="\
             """

    assert O.authorization([
             {"(request-target)", "post /foo?param=value&pet=dog"},
             {"host", "example.com"},
             {"date", "Thu, 05 Jan 2014 21:31:40 GMT"}
           ]) ==
             ~S[Signature version="1",keyId="Test",algorithm="rsa-sha256",headers="(request-target) host date",signature="HUxc9BS3P/kPhSmJo+0pQ4IsCo007vkv6bUm4Qehrx+B1Eo4Mq5/6KylET72ZpMUS80XvjlOPjKzxfeTQj4DiKbAzwJAb4HX3qX6obQTa00/qPDXlMepD2JtTw33yNnm/0xV7fQuvILN/ys+378Ysi082+4xBQFwvhNvSoVsGv4="]
  end

  defp put_test_env(env) do
    env_before = Application.get_all_env(:o)
    :ok = Application.put_all_env(o: env)

    on_exit(fn ->
      Enum.each(env, fn {k, _} -> Application.delete_env(:o, k) end)
      Application.put_all_env(o: env_before)
    end)
  end
end
