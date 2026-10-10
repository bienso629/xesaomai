import asyncio
import json
import urllib.request
import websockets
import base64
import subprocess
import time

p = subprocess.Popen([
    "google-chrome",
    "--headless=new",
    "--disable-gpu",
    "--remote-debugging-port=9333",
    "http://localhost:8088"
])
time.sleep(3)

async def dump():
    try:
        req = urllib.request.urlopen("http://localhost:9333/json")
        tabs = json.loads(req.read().decode())
        page_tab = [t for t in tabs if t.get('type') == 'page' and '8088' in t.get('url', '')][0]
        ws_url = page_tab['webSocketDebuggerUrl']
        
        async with websockets.connect(ws_url) as ws:
            # Enable Runtime and Log
            await ws.send(json.dumps({"id": 1, "method": "Runtime.enable"}))
            await ws.send(json.dumps({"id": 2, "method": "Log.enable"}))
            await ws.send(json.dumps({"id": 3, "method": "Page.enable"}))
            
            # Capture screenshot
            await asyncio.sleep(2)
            await ws.send(json.dumps({"id": 4, "method": "Page.captureScreenshot"}))
            while True:
                resp = await ws.recv()
                data = json.loads(resp)
                if data.get("id") == 4:
                    img_data = data["result"]["data"]
                    with open("/home/yenai/Documents/Projects/Taxi/page_screenshot.png", "wb") as f:
                        f.write(base64.b64decode(img_data))
                    print("Screenshot saved to /home/yenai/Documents/Projects/Taxi/page_screenshot.png")
                    break
    except Exception as e:
        print("Exception:", e)
    finally:
        p.terminate()

asyncio.run(dump())
