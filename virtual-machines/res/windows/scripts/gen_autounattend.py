import json, sys
with open(sys.argv[1], "r") as f:
    config = json.load(f)
admin_username = config["adminUserName"]
user_data = sys.stdin.read() \
    .replace("${ADMIN_USERNAME_PLACEHOLDER}", admin_username)
sys.stdout.write(user_data)
