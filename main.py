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
