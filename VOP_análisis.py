import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from scipy.signal import butter, freqz, filtfilt, correlate, find_peaks, iirnotch
from scipy import signal


# Filtrado pasa bajos (elimina ruido por encima de 10 Hz aprox.)
def lowpass_filter(signal, fs=512, cutoff=30, order=4):
    nyq = 0.5 * fs
    normal_cutoff = cutoff / nyq
    b, a = butter(order, normal_cutoff, btype='low')
    return filtfilt(b, a, signal)

# Filtro pasa altos (elimina frecuencia respiratoria o desplazamiento de línea base)
def highpass_filter(signal, fs=512, cutoff=0.5, order=4):
    nyq = 0.5 * fs
    normal_cutoff = cutoff / nyq
    b, a = butter(order, normal_cutoff, btype='high')
    return filtfilt(b, a, signal)


# Filtro notch (elimina frecuencia específica, como 50 Hz)
def notch_filter(signal, fs=512, notch_freq=50.0, Q=30.0):
    # notch_freq: frecuencia a eliminar
    # Q: factor de calidad (cuanto más alto, más estrecha la banda rechazada)
    w0 = notch_freq / (0.5 * fs)  # Normalizar frecuencia
    b, a = iirnotch(w0, Q)
    return filtfilt(b, a, signal)
# Normalizar
def normalize(signal):
    return (signal - np.mean(signal)) / np.std(signal)

# Parámetros del filtro
fs = 512         # Frecuencia de muestreo
cutoff = 20      # Frecuencia de corte del pasa bajos
order = 4        # Orden del filtro

# Crear el filtro
nyq = 0.5 * fs
normal_cutoff = cutoff / nyq
b, a = butter(order, normal_cutoff, btype='low')

# Calcular respuesta en frecuencia
w, h = freqz(b, a, worN=8000)
frequencies = w * fs / (2 * np.pi)

# Cargar el CSV (ajustá el nombre si es otro)
df = pd.read_csv(path2, skiprows=3, names=["Tiempo", "Señal1", "Señal2"])

# Convertir strings a números
df["Tiempo"] = pd.to_numeric(df["Tiempo"], errors='coerce')
df["Señal1"] = pd.to_numeric(df["Señal1"], errors='coerce')
df["Señal2"] = pd.to_numeric(df["Señal2"], errors='coerce')

# Eliminar filas con valores nulos
df = df.dropna()

# Extraer arrays como float64
t = df["Tiempo"].astype(float).to_numpy()
ba = df["Señal1"].astype(float).to_numpy()  # Brachial
an = df["Señal2"].astype(float).to_numpy()  # Tibial

# Filtrar ambas señales
ba_filt = highpass_filter(ba, fs)
an_filt = highpass_filter(an, fs)

ba_filt = lowpass_filter(ba_filt, fs)
an_filt = lowpass_filter(an_filt, fs)

ba_filt = notch_filter(ba_filt, fs)
an_filt = notch_filter(an_filt, fs)

# Normalizar (especialmente importante para tibial)
ba_norm = normalize(ba_filt)
an_norm = normalize(an_filt)

# Extraer arrays como float64
t = df["Tiempo"].astype(float).to_numpy()
ba = df["Señal1"].astype(float).to_numpy()  # Brachial
an = df["Señal2"].astype(float).to_numpy()  # Tibial

# Calcular frecuencia de muestreo
fs = 512

# Parámetros
min_distance = int(fs * 0.5)
prom_ba = 0.5  # para señal normalizada
prom_an = 0.07 # más baja para detectar tibial

# Detectar picos
peaks_brachial, _ = find_peaks(ba_filt, distance=min_distance, prominence=prom_ba)
peaks_tibial, _ = find_peaks(an_filt, distance=min_distance, prominence=prom_an)

max_time_diff = 0.2  # segundos
ptt_list = []

for pb in peaks_brachial:
    time_b = t[pb]
    time_diffs = t[peaks_tibial] - time_b
    valid_indices = np.where(time_diffs > 0)[0]

    if len(valid_indices) > 0:
        valid_time_diffs = time_diffs[valid_indices]
        min_idx_in_valid = np.argmin(valid_time_diffs)
        min_idx = valid_indices[min_idx_in_valid]

        if time_diffs[min_idx] <= max_time_diff:
            pt = time_diffs[min_idx]
            ptt_list.append(pt)
            print(f"Emparejado: Radial @ {time_b:.3f}s → Tibial @ {t[peaks_tibial[min_idx]]:.3f}s → PTT = {pt*1000:.2f} ms")
    else:
        print(f"No se encontró pico tibial posterior a braquial en {time_b:.3f}s")

altura = 162
Dhb = (0.300*altura - 2.07)/100
Dhf = (0.564*altura - 18.4)/100
Dfa = (0.249*altura + 30.7)/100
VOP = []
for i in ptt_list:
  if float((Dfa + Dhf - Dhb) / i) < 40:
    VOP.append(float((Dfa + Dhf - Dhb) / i))
print(VOP)
mediana_vop = np.median(VOP)
print(f"Mediana VOP: {mediana_vop:.4f} m/s")