require 'openssl'

module Encryption

  def key=(key)
    @symmetric_key = key
  end

  def make_cipher
    OpenSSL::Cipher::AES.new(128, :CBC)
  end

  # Returns [encrypted, iv]
  def encrypt(data)
    cipher = make_cipher.encrypt
    cipher.key = @symmetric_key
    iv = cipher.random_iv
    [cipher.update(data) + cipher.final, iv]
  end

  def decrypt(data, iv)
    decipher = make_cipher.decrypt
    decipher.key = @symmetric_key
    decipher.iv = iv
    decipher.update(data) + decipher.final
  end

  # Same sort of thing /etc/passwd uses.
  # Provides no security against snooping passwords off
  # the wire, but does make it safer to handle the user
  # password file.
  def make_password_hash(password)
    password.crypt('RB')
  end
end
