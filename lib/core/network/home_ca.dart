/// The home server's internal Caddy signs `*.shaddai.home` (Kapowarr at
/// `https://reader.shaddai.home/kapowarr`, and the same-origin proxies)
/// with its own "local authority" (`tls internal`). Browsers on the owner's
/// PCs trust it; the app's Dart network stack doesn't, so those requests
/// failed with "unable to get local issuer certificate". main() adds this
/// root to the trusted set on native platforms. It's a public certificate;
/// Caddy keeps the private key. Valid until 2036-05-19; if Caddy's data
/// volume is ever recreated it issues a new root, and this must be replaced
/// (`docker exec caddy cat /data/caddy/pki/authorities/local/root.crt`).
const homeCaPem = '''
-----BEGIN CERTIFICATE-----
MIIBojCCAUmgAwIBAgIQdD7cphfur6oVorQ9xtXN0TAKBggqhkjOPQQDAjAwMS4w
LAYDVQQDEyVDYWRkeSBMb2NhbCBBdXRob3JpdHkgLSAyMDI2IEVDQyBSb290MB4X
DTI2MDcxMTEwMTE1OVoXDTM2MDUxOTEwMTE1OVowMDEuMCwGA1UEAxMlQ2FkZHkg
TG9jYWwgQXV0aG9yaXR5IC0gMjAyNiBFQ0MgUm9vdDBZMBMGByqGSM49AgEGCCqG
SM49AwEHA0IABCh+4V7MPTnrUdeMUJq/9/9jtemIt1LaYX9HTOuW/BrNnKaBLN8y
0xWsq7ItZKUp3I2fD9vhq1jo2z0yZMpD5yujRTBDMA4GA1UdDwEB/wQEAwIBBjAS
BgNVHRMBAf8ECDAGAQH/AgEBMB0GA1UdDgQWBBRtxfoVTypBNLz3vJnfymCLuRLs
PTAKBggqhkjOPQQDAgNHADBEAiB2/Xnm8/rdvfmluLp26dauYD3tUrN2rMymgApv
NVx8igIgTKHgCDi1hV8L3AdzZ9CsG0WADRSq1bIm43BXpfg3dAw=
-----END CERTIFICATE-----
''';
