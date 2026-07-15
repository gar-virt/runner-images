import json, sys
with open(sys.argv[1], "r") as f:
    config = json.load(f)
admin_username = config["adminUserName"]
ssh_public_key = config["sshPublicKey"]
docker_tag = config["dockerTag"]
user_data = sys.stdin.read() \
    .replace("${ADMIN_USERNAME_PLACEHOLDER}", admin_username) \
    .replace("${SSH_PUBLIC_KEY_PLACEHOLDER}", ssh_public_key) \
    .replace("${DOCKER_TAG_PLACEHOLDER}", docker_tag)
sys.stdout.write(user_data)
