import argparse
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import urllib.request


def download_file(url):
    with urllib.request.urlopen(url) as response:
        with tempfile.NamedTemporaryFile(delete=False) as f:
            shutil.copyfileobj(response, f)
            return f.name


def verify_file_sha256(file, expected_digest):
    with open(file, "rb") as f:
        digest = hashlib.file_digest(f, "sha256").hexdigest().casefold()
        if digest != expected_digest.casefold():
            raise Exception("Invalid hash: File {} hashed to {}, expected {}".format(
                file, digest, expected_digest))


def replace_placeholders(template, resolver):
    return re.sub(r"\$\{([^\}]+)\}", lambda m: resolver(m[1]), template)


allowed_transform_functions = {
    "replace": lambda self, search, replacement: self.replace(search, replacement)
}


def resolve_placeholder(expr, entry):
    if "|" in expr:
        key, transform = expr.split("|")
        value = entry[key]
        value = replace_placeholders(
            value, lambda m: resolve_placeholder(m, entry))
        value = eval(r"{}.{}".format(key, transform),
                     allowed_transform_functions, {key: value})
    else:
        key = expr
        value = entry[key]
        value = replace_placeholders(
            value, lambda m: resolve_placeholder(m, entry))
    return value


def expand_placeholders(value, entry):
    return replace_placeholders(value, lambda m: resolve_placeholder(m, entry))


def expand_entry_vars(entry):
    for k, v in entry.items():
        entry[k] = expand_placeholders(v, entry)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("spec")
    parser.add_argument("-b", "--base-dir")
    return parser.parse_args()


def main(args):
    spec_path = os.path.realpath(args.spec)
    base_dir = os.path.dirname(os.path.realpath(
        spec_path)) if args.base_dir is None else os.path.realpath(args.base_dir)
    with open(spec_path, "r") as f:
        spec_content = re.sub(r"^\s*//.*", "", f.read(), flags=re.MULTILINE)
        spec_entries = json.loads(spec_content)
    for entry in spec_entries:
        expand_entry_vars(entry)
        name = entry["name"]
        version = entry["version"]
        filename = entry["filename"]
        sha256_hash = entry["sha256_hash"]
        url = entry["url"]
        dest_path = os.path.join(base_dir, entry["destination"], filename)
        print("{} {}...".format(name, version))
        try:
            if os.path.exists(dest_path):
                verify_file_sha256(dest_path, sha256_hash)
            else:
                downloaded_file_path = None
                try:
                    downloaded_file_path = download_file(url)
                    verify_file_sha256(downloaded_file_path, sha256_hash)
                    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                    shutil.move(downloaded_file_path, dest_path)
                finally:
                    if downloaded_file_path is not None and os.path.exists(downloaded_file_path):
                        os.unlink(downloaded_file_path)
        except Exception as e:
            print("ERROR: {}".format(str(e)), file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(parse_args()))
