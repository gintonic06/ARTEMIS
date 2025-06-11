from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio
import json
import time

app = FastAPI()

arduino_ws = None  # Aquí guardamos el WebSocket del Arduino
flutter_clients = set()  # Clientes Flutter conectados

@app.websocket("/ws/arduino")
async def arduino_endpoint(websocket: WebSocket):
    global arduino_ws
    await websocket.accept()
    print("Arduino conectado")
    arduino_ws = websocket
    try:
        while True:
            data = await websocket.receive_text()
            print(f"Datos recibidos de Arduino: {data}")
            # Reenviar a todos los clientes Flutter conectados
            for client in flutter_clients:
                try:
                    await client.send_text(data)
                except Exception as e:
                    print(f"Error enviando a Flutter: {e}")
    except WebSocketDisconnect:
        print("Arduino desconectado")
        arduino_ws = None

@app.websocket("/ws/flutter")
async def flutter_endpoint(websocket: WebSocket):
    await websocket.accept()
    flutter_clients.add(websocket)
    print("Cliente Flutter conectado")
    try:
        while True:
            message = await websocket.receive_text()
            print(f"Mensaje recibido de Flutter: {message}")
            # Flutter puede enviar comandos 'start' o 'stop' para Arduino
            if arduino_ws:
                await arduino_ws.send_text(message)
    except WebSocketDisconnect:
        print("Cliente Flutter desconectado")
        flutter_clients.remove(websocket)

@app.get("/")
def root():
    return {"message": "Servidor FastAPI con WebSockets para Arduino y Flutter corriendo"}




"""from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio
import json
import math
import time
import httpx

app = FastAPI()

arduino_url = "http://172.20.10.2/data"
connected_clients = set()
clients_states = dict()
send_tasks = dict()

# Parámetros de la señal
frequency = 1  # 1 Hz (un ciclo por segundo)
sampling_rate = 50  # muestras por segundo
phase_shift = 0.1  # 100 ms
amplitude = 1.0

async def send_data_to_client(websocket: WebSocket):
    t = 0
    dt = 1 / sampling_rate
    try:
        while clients_states.get(websocket, False):
            braquial = amplitude * math.sin(2 * math.pi * frequency * t)
            tibial = amplitude * math.sin(2 * math.pi * frequency * (t - phase_shift))

            data = {
                "timestamp": time.time(),
                "braquial": braquial,
                "tibial": tibial
            }

            await websocket.send_text(json.dumps(data))
            t += dt
            await asyncio.sleep(dt)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Error enviando datos: {e}")
    finally:
        clients_states[websocket] = False


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Cliente conectado")
    connected_clients.add(websocket)
    clients_states[websocket] = False

    try:
        while True:
            message = await websocket.receive_text()
            print(f"Mensaje recibido del cliente: {message}")

            if message == "start":
                if not clients_states.get(websocket, False):
                    clients_states[websocket] = True
                    send_tasks[websocket] = asyncio.create_task(send_data_to_client(websocket))
            elif message == "stop":
                if clients_states.get(websocket, False):
                    clients_states[websocket] = False
                    task = send_tasks.get(websocket)
                    if task:
                        task.cancel()
                        del send_tasks[websocket]
    except WebSocketDisconnect:
        print("Cliente desconectado")
    finally:
        connected_clients.remove(websocket)
        clients_states.pop(websocket, None)
        task = send_tasks.get(websocket)
        if task:
            task.cancel()
            send_tasks.pop(websocket, None)

@app.get("/")
def read_root():
    return {"message": "Servidor FastAPI corriendo con WebSocket en /ws"}
"""