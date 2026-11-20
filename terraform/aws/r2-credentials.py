import json
import os
import sys

# The backend selects this profile explicitly, keeping AWS provider credentials separate.
names = ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY")
if any(not os.environ.get(name) for name in names):
    sys.exit("R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY must be set")

print(json.dumps({
    "Version": 1,
    "AccessKeyId": os.environ[names[0]],
    "SecretAccessKey": os.environ[names[1]],
}))
