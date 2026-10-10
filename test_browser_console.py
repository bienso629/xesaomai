import subprocess
import time
import json
import urllib.request

# Run headless chrome to inspect console logs and page errors
cmd = [
    "google-chrome",
    "--headless=new",
    "--disable-gpu",
    "--remote-debugging-port=9222",
    "http://localhost:8088"
]
p = subprocess.Popen(cmd)
time.sleep(3)

try:
    req = urllib.request.urlopen("http://localhost:9222/json")
    tabs = json.loads(req.read().decode())
    print("Tabs:", tabs)
except Exception as e:
    print("Error connecting to Chrome debugging port:", e)
finally:
    p.terminate()
