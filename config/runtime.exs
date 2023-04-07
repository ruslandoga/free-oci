import Config

if config_env() in [:dev, :prod] do
  config :o,
    region: System.fetch_env!("OCI_REGION"),
    tenancy: System.fetch_env!("OCI_TENANCY"),
    user: System.fetch_env!("OCI_USER"),
    fingerprint: System.fetch_env!("OCI_FINGERPRINT"),
    private_key: System.fetch_env!("OCI_PRIVATE_KEY"),
    public_key: System.fetch_env!("OCI_PUBLIC_KEY"),
    subnet_id: System.fetch_env!("OCI_SUBNET_ID")
end
