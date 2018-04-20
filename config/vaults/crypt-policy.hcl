path "crypt/keystore/*" {
  policy = "write"
}

path "crypt/deviceSigningKeys/*" {
  policy = "write"
}

path "sys/mounts/pkis/*" {
  policy = "write"
}

path "pkis/crypt/*" {
  policy = "write"
}
