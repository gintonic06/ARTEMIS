from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio
import json
import time
import numpy as np
import json
import pandas as pd
import matplotlib.pyplot as plt
from scipy.signal import butter, filtfilt, correlate, find_peaks, iirnotch
from scipy import signal

app = FastAPI()

arduino_ws = None  # Aquí guardamos el WebSocket del Arduino
flutter_clients = set()  # Clientes Flutter conectados

datos = []
altura = None

# Filtrado pasa bajos (elimina ruido por encima de 10 Hz aprox.)
def lowpass_filter(signal, fs = 50, cutoff = 16, order=4):
    nyq = 0.5 * fs
    normal_cutoff = cutoff / nyq
    b, a = butter(order, normal_cutoff, btype='low')
    return filtfilt(b, a, signal)

# Filtro pasa altos (elimina frecuencia respiratoria o desplazamiento de línea base)
def highpass_filter(signal, fs = 50, cutoff = 0.5, order=4):
    nyq = 0.5 * fs
    normal_cutoff = cutoff / nyq
    b, a = butter(order, normal_cutoff, btype='high')
    return filtfilt(b, a, signal)


# Filtro notch (elimina frecuencia específica, como 50 Hz)
def notch_filter(signal, fs = 50, notch_freq=24, Q=30.0):
    # notch_freq: frecuencia a eliminar
    # Q: factor de calidad (cuanto más alto, más estrecha la banda rechazada)
    w0 = notch_freq / (0.5 * fs)  # Normalizar frecuencia
    b, a = iirnotch(w0, Q)
    return filtfilt(b, a, signal)
# Normalizar
def normalize(signal):
    return (signal - np.mean(signal)) / np.std(signal)

def calcular_vop(datos_json, altura_cm):
    df = pd.DataFrame(datos_json)

    df["t"] = pd.to_numeric(df["t"], errors='coerce')
    df["braquial"] = pd.to_numeric(df["braquial"], errors='coerce')
    df["tibial"] = pd.to_numeric(df["tibial"], errors='coerce')
    df = df.dropna()

    t = df["t"].astype(float).to_numpy()
    ba = df["braquial"].astype(float).to_numpy()
    an = df["tibial"].astype(float).to_numpy()
    t = (t - t[0]) / 1000.0  # ms → s

    fs = 50
    ba_filt = lowpass_filter(highpass_filter(ba, fs), fs)
    an_filt = lowpass_filter(highpass_filter(an, fs), fs)
    ba_norm = normalize(ba_filt)
    an_norm = normalize(an_filt)

    peaks_ba, _ = find_peaks(ba_norm, distance=1, prominence=0.3)
    peaks_an, _ = find_peaks(an_norm, distance=1, prominence=0.1)

    ptt_list = []
    for pb in peaks_ba:
        time_b = t[pb]
        time_diffs = t[peaks_an] - time_b
        valid_indices = np.where(time_diffs > 0)[0]
        if len(valid_indices) > 0:
            min_idx_in_valid = np.argmin(time_diffs[valid_indices])
            pt = time_diffs[valid_indices[min_idx_in_valid]]
            if 0.15 <= pt <= 0.35:
                ptt_list.append(pt)

    if not ptt_list:
        return []

    altura = altura_cm
    Dhb = (0.220*altura - 2.07)/100
    Dhf = (0.564*altura - 18.4)/100
    Dfa = (0.249*altura + 30.7)/100

    vop = [(Dfa + Dhf - Dhb) / i for i in ptt_list if (Dfa + Dhf - Dhb) / i < 40]
    
    # Obtener tiempos de los picos braquiales
    times_brachial = t[peaks_ba]

    # Calcular diferencias entre tiempos consecutivos
    rr_intervals = np.diff(times_brachial)  # en segundos

    # Filtrar intervalos razonables (entre 0.3s y 1.0s por ejemplo)
    valid_rr = rr_intervals[(rr_intervals > 0.4) & (rr_intervals < 1.0)]

    # Calcular frecuencia de pulso promedio (Hz y bpm)
    if len(valid_rr) > 0:
        mean_rr = np.median(valid_rr)
        freq_hz = 1 / mean_rr
        freq_bpm = freq_hz * 60
    return vop, freq_bpm



@app.websocket("/ws/arduino")
async def arduino_endpoint(websocket: WebSocket):
    global arduino_ws, datos
    await websocket.accept()
    print("Arduino conectado")
    arduino_ws = websocket
    try:
        while True:
            data = await websocket.receive_text()
            print(f"Datos recibidos de Arduino: {data}")

            # Guardar datos para cálculo de VOP
            try:
                lectura = json.loads(data)
                datos.append(lectura)
            except Exception as e:
                print(f"Error procesando dato: {e}")

            # Reenviar a Flutter
            for client in list(flutter_clients):
                try:
                    await asyncio.wait_for(client.send_text(data), timeout=0.1)
                except asyncio.TimeoutError:
                    print("Flutter tardó demasiado en recibir. Ignorando mensaje.")
                except Exception as e:
                    print(f"Error enviando a Flutter: {e}")
                    flutter_clients.remove(client)
    except WebSocketDisconnect as e:
        print(f"Arduino desconectado por {e}")
        arduino_ws = None




@app.websocket("/ws/flutter")
async def flutter_endpoint(websocket: WebSocket):
    global altura, datos
    await websocket.accept()
    flutter_clients.add(websocket)
    print("Cliente Flutter conectado")

    try:
        while True:
            message = await websocket.receive_text()
            print(f"Mensaje recibido de Flutter: {message}")

            # Detectar comandos start/stop simples
            if message.lower() == "start":
                print("Recibido comando START")
                datos = []  # limpiar datos previos

            elif message.lower() == "stop":
                print("Recibido comando STOP. Procesando VOP...")
                if altura and datos:
                    vop_values, freq = calcular_vop(datos, altura)
                    datos = []
                    if vop_values:
                        mediana = np.median(vop_values)
                        await websocket.send_text(json.dumps({"vop": round(mediana, 2)}))
                        await websocket.send_text(json.dumps({"freq": round(freq, 0)}))
                    else:
                        await websocket.send_text(json.dumps({"error": "No se pudo calcular la VOP"}))
                else:
                    print("Faltan datos o altura")
                    await websocket.send_text(json.dumps({"error": "Faltan datos o altura"}))

            else:
                # Intentar obtener altura si es JSON
                try:
                    msg = json.loads(message)
                    if msg.get("command") == "set_altura":
                        altura = msg.get("altura")
                        print(f"Altura recibida: {altura} cm")
                except Exception:
                    pass  # no es JSON válido, ignorar

            # **Reenviar todos los mensajes a Arduino, siempre que Arduino esté conectado**
            if arduino_ws:
                await arduino_ws.send_text(message)

    except WebSocketDisconnect:
        print("Cliente Flutter desconectado")
        flutter_clients.remove(websocket)


@app.get("/")
def root():
    return {"message": "Servidor FastAPI con WebSockets para Arduino y Flutter corriendo"}
