key_provider    = Auth.key_provider
secret_key_base = key_provider.to_binary "3998a7a8a8495fc062a4e34f5e639a19cd95aba41edac175fcb4928fce00b238c113e1b08e279016a45c67ad2a18564dbc9610dfcd259314739efcacc0e729c2"
salt            = key_provider.to_binary "fac022554f9eff9239832696c6afb68e93b6cc3563b29185db5c83e7a4816fe7267fe121b036810f51fbead4178b64b9f4945b7732c4aebe7a76a06df0b21c2f"

Auth.origin          = "http://localhost:3000"
Auth.relaying_party  = "Dummy Test"
Auth.salt            = salt
Auth.app_private_key = key_provider.private_key(secret_key_base, salt: salt)
Auth.app_public_key  = Auth.app_private_key.public_key

Auth.argon2_opslimit = 3
Auth.argon2_memlimit = 2**13

Auth.jwt_secret = SecureRandom.hex(64)
Auth.secret_key_base = secret_key_base
