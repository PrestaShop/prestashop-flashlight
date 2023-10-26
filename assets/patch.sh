#!/bin/bash
set -eu

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "${PS_FOLDER}/VERSION")

patch_1_6 () {
  # Add robots file
  echo "User-agent: *" > "${PS_FOLDER}/robots.txt"
  echo "Disallow: /" >> "${PS_FOLDER}/robots.txt"

  # Fix the _RIJNDAEL_KEY_ warnings
  sed -i "s/(_RIJNDAEL_KEY_, _RIJNDAEL_IV_)/('_RIJNDAEL_KEY_', '_RIJNDAEL_IV_')/" \
    "$PS_FOLDER/classes/Cookie.php"
  sed -i "s/MCRYPT_RIJNDAEL_128/'MCRYPT_RIJNDAEL_128'/" \
    "$PS_FOLDER/classes/Rijndael.php"
  sed -i "s/MCRYPT_MODE_CBC/'MCRYPT_MODE_CBC'/" \
    "$PS_FOLDER/classes/Rijndael.php"

  # Fix the Rijndael keys length
   # shellcheck disable=SC2016
  sed -i 's/$this->_key = $key/$this->_key = openssl_random_pseudo_bytes(32)/' \
    "$PS_FOLDER/classes/Rijndael.php"
  # shellcheck disable=SC2016
  sed -i 's/$this->_iv = base64_decode($iv)/$this->_iv = openssl_random_pseudo_bytes(16)/' \
    "$PS_FOLDER/classes/Rijndael.php"
}

echo "$PS_VERSION" | grep "^1.6" > /dev/null && patch_1_6 || echo "coucou"
