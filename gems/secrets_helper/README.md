## Secret Helper

Various methods for working with encrypted URL strings, random codes, and signed tickets.

### Encrypted URLs

Create encrypted text for URLs. The resulting ciphertext is long,
but secure and verified.

```ruby
    ENV['SECRET_KEY_NAME'] = 'xxxxx'
    encrypted_parameter = SecretUrl::encrypt('hello', 'secret_key_name')
    cleartext = SecretUrl::decrypt(encrypted_parameter, 'secret_key_name')
    puts cleartext
    > "hello"
```

### Random Codes

Generate a user friendly code, like for recovery codes, coupon codes, etc. It will
not include ambiguous characters (e.g. one and I).

    puts RandomCode.create(8)
    > "dqbjytc4"

    puts RandomCode.create(12, 4).upcase
    > "DQBJ-YTC4-978T"

### Encoded Numbers in URLs

Sometimes you want to include numbers or IDs in URLs but encryption is overkill
for your usage. TinyUrl will obfuscate an integer for a URL, typically making it
shorter.

There are two modes: a basic mode and an XOR mode.

**The basic mode**

Basic mode simply base-64 encodes the number. It is easily reversible by anyone.

```ruby
encoded_str = TinyUrl.encode(1000000)
puts encoded_str
> QEIP

# later...
puts TinyUrl.decode("QEIP")
> 1000000
```

**The XOR mode**

In this mode, it XORs the input number, converts to base 64 encoding, and adds two
checksum digits to the string.

The resulting encoded string has the following properties:

* You need the XOR secret to decode the string into a number, which means if you
  change the secret it will invalidate all previously generated encodings.

* There is a 1:4096 chance that a random string will decode into a number
  (because we only use 12 checksum bits).

* The encodings appear to be random, but are determinist: the same secret and
  the same number will always produce the same encoding.

The XOR secret can be derived if you know the input and output of an encoding,
or if one can run frequency analysis on the encodings (it is just XOR after
all). So, do not use XOR mode if the input number is ever visible to the user.

If your application does something expensive when a valid TinyUrl is specified,
then an attacker could use timing attacks to generate a set of valid encodings
and then use that to derive the XOR secret.

In sort, TinyUrls are nifty, but not remotely appropriate for anything sensitive.

```ruby
ENV['MY_SECRET'] = "shhhhh"
encoded_str = TinyUrl.encode(1000000, 'my_secret')
puts encoded_str
> oQDuEH

# later...
puts TinyUrl.decode("oQDuEH", 'my_secret')
> 1000000
```
