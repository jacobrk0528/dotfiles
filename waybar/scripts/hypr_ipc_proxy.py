#!/usr/bin/env python3
import os
import sys
import socket
import threading
import time

def main():
    real_sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not real_sig:
        sys.exit("HYPRLAND_INSTANCE_SIGNATURE not set")

    xdg = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    real_cmd_path = f"{xdg}/hypr/{real_sig}/.socket.sock"
    real_evt_path = f"{xdg}/hypr/{real_sig}/.socket2.sock"

    proxy_sig = f"proxy_{real_sig}"
    proxy_dir = f"{xdg}/hypr/{proxy_sig}"
    os.makedirs(proxy_dir, exist_ok=True)

    proxy_cmd_path = f"{proxy_dir}/.socket.sock"
    proxy_evt_path = f"{proxy_dir}/.socket2.sock"

    for p in (proxy_cmd_path, proxy_evt_path):
        if os.path.exists(p):
            try:
                os.remove(p)
            except OSError:
                pass

    cmd_server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    cmd_server.bind(proxy_cmd_path)
    cmd_server.listen(10)

    def handle_cmd(client):
        try:
            data = client.recv(4096)
            if not data:
                client.close()
                return
            cmd = data.decode("utf-8", errors="replace").strip()

            if cmd.startswith("dispatch workspace "):
                ws = cmd[len("dispatch workspace "):]
                if ws.isdigit():
                    cmd = f"dispatch hl.dsp.focus({{ workspace = {ws} }})"
                else:
                    cmd = f"dispatch hl.dsp.exec_raw(\"workspace {ws}\")"

            real_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            real_sock.connect(real_cmd_path)
            real_sock.sendall(cmd.encode("utf-8"))
            
            # Receive full response (could be large JSON for workspaces/clients)
            while True:
                res = real_sock.recv(16384)
                if not res:
                    break
                client.sendall(res)
            real_sock.close()
        except Exception:
            pass
        finally:
            client.close()

    def cmd_loop():
        while True:
            try:
                client, _ = cmd_server.accept()
                threading.Thread(target=handle_cmd, args=(client,), daemon=True).start()
            except Exception:
                break

    evt_server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    evt_server.bind(proxy_evt_path)
    evt_server.listen(10)

    def handle_evt(client):
        try:
            real_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            real_sock.connect(real_evt_path)
            while True:
                data = real_sock.recv(16384)
                if not data:
                    break
                client.sendall(data)
            real_sock.close()
        except Exception:
            pass
        finally:
            client.close()

    def evt_loop():
        while True:
            try:
                client, _ = evt_server.accept()
                threading.Thread(target=handle_evt, args=(client,), daemon=True).start()
            except Exception:
                break

    t1 = threading.Thread(target=cmd_loop, daemon=True)
    t2 = threading.Thread(target=evt_loop, daemon=True)
    t1.start()
    t2.start()

    print(proxy_sig, flush=True)

    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()
