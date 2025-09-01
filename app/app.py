import os, subprocess, time
from flask import Flask, jsonify, request

app = Flask(__name__)

def run_matmul():
    try:
        start = time.time()
        # call the demo binary; if not present, fall back to a dummy CPU matmul
        out = subprocess.run(["/usr/local/bin/matmul_demo"], capture_output=True, text=True, timeout=120)
        elapsed = time.time() - start
        return {"ok": out.returncode == 0, "output": out.stdout.strip(), "elapsed_sec": elapsed}
    except FileNotFoundError:
        # CPU fallback calculation
        import random
        n = 256
        A = [[random.random() for _ in range(n)] for _ in range(n)]
        B = [[random.random() for _ in range(n)] for _ in range(n)]
        C = [[0.0]*n for _ in range(n)]
        t0 = time.time()
        for i in range(n):
            for k in range(n):
                aik = A[i][k]
                for j in range(n):
                    C[i][j] += aik * B[k][j]
        return {"ok": True, "output": "CPU fallback %dx%d matmul done" % (n,n), "elapsed_sec": time.time()-t0}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@app.get("/healthz")
def healthz():
    return "ok", 200

@app.get("/compute")
def compute():
    res = run_matmul()
    return jsonify(res), 200 if res.get("ok") else 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
