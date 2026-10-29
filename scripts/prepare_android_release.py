"""Fail before building if Play signing is incomplete. Never print secrets."""
import base64
import os
from pathlib import Path

REQUIRED = (
    'ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD',
)
# Play API access is keyless (GitHub OIDC -> Workload Identity Federation), so
# no Google credential is stored as a repository secret.


def property_value(value):
    # Java Properties escapes, including spaces and non-ASCII passwords.
    result = ''
    for char in value:
        if char in '\\=:#! ':
            result += '\\' + char
        elif char == '\n':
            result += '\\n'
        elif char == '\r':
            result += '\\r'
        elif char == '\t':
            result += '\\t'
        elif ord(char) > 126:
            encoded = char.encode('utf-16-be')
            result += ''.join(f'\\u{int.from_bytes(encoded[i:i+2], "big"):04x}' for i in range(0, len(encoded), 2))
        else:
            result += char
    return result


def main():
    missing = [key for key in REQUIRED if not os.environ.get(key)]
    if missing:
        raise SystemExit('Google Play release setup is incomplete. Add repository Actions secrets: ' + ', '.join(missing))
    os.umask(0o077)
    temp = Path(os.environ['RUNNER_TEMP'])
    keystore = temp / 'foorsa-upload.jks'
    keystore.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'], validate=True))
    values = {
        'storeFile': str(keystore),
        'storePassword': os.environ['ANDROID_KEYSTORE_PASSWORD'],
        'keyAlias': os.environ['ANDROID_KEY_ALIAS'],
        'keyPassword': os.environ['ANDROID_KEY_PASSWORD'],
    }
    Path('android/key.properties').write_text(''.join(f'{key}={property_value(value)}\n' for key, value in values.items()))


if __name__ == '__main__':
    main()
