#!/bin/bash

# ====================================================================
# SCRIPT UNIFICADO: PRUEBAS IPERF3 (6 VECES) + GUARDADO + PROMEDIO
# ====================================================================

# --- Configuración del Test iperf3 ---
SERVIDOR="certificaciones.metrotel.com.ar"
DURACION_TEST=5    # Duración de CADA test iperf3 en segundos (-t 5)
MAX_ITERACIONES=6  # Número total de pruebas a ejecutar
FICHERO_TEMPORAL="iperf3_temp.json"      # Archivo temporal para el JSON de cada prueba
FICHERO_OUTPUT="iperf3_raw_output.txt"   # Archivo de salida final con todos los JSONs

# --- Variables Globales para Totales ---
# Se usan arrays para recolectar todos los valores de Mbps antes de promediar
SENDER_VALUES=()
RECEIVER_VALUES=()
NUM_FALLAS=0 

# --- Dependencias Requeridas ---
DEPENDENCIAS=("iperf3" "jq" "bc") 

# --------------------------------------------------------------------
# FUNCIÓN DE LIMPIEZA
# --------------------------------------------------------------------
cleanup() {
    rm -f "$FICHERO_TEMPORAL"
    echo ""
    echo "Script finalizado. Archivo temporal limpiado."
}
trap cleanup EXIT

# --------------------------------------------------------------------
# FUNCIÓN DE INSTALACIÓN
# --------------------------------------------------------------------
install_dependencies() {
    echo "--- 🛠️  Verificación de Dependencias ---"
    
    for cmd in "${DEPENDENCIAS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ ERROR: El comando '$cmd' no está instalado. Instálalo manualmente para continuar."
            exit 1
        else
            echo "✅ El comando '$cmd' ya está disponible."
        fi
    done
    
    # Limpiar archivo de salida anterior y temporal
    > "$FICHERO_OUTPUT" 
    rm -f "$FICHERO_TEMPORAL"
    echo "--- Dependencias OK. Archivo '$FICHERO_OUTPUT' listo para recibir datos. ---"
}

# --------------------------------------------------------------------
# FUNCIÓN PRINCIPAL DE MONITOREO IPERF3
# --------------------------------------------------------------------
run_iperf_monitor() {
    echo ""
    echo "--- 🚀 Iniciando Generación de Datos de iperf3 ---"
    echo "Servidor: $SERVIDOR | Pruebas a realizar: $MAX_ITERACIONES"
    echo "----------------------------------------------------"
    
    local CONTADOR=0
    
    while [ $CONTADOR -lt $MAX_ITERACIONES ]; do
        CONTADOR=$((CONTADOR + 1))
        echo "Ejecutando test #$CONTADOR de $MAX_ITERACIONES..."
        
        iperf3 -c "$SERVIDOR" -t "$DURACION_TEST" -J > "$FICHERO_TEMPORAL" 2>/dev/null
        cat "$FICHERO_TEMPORAL" >> "$FICHERO_OUTPUT"

        # --- LÓGICA DE EXTRACCIÓN Y RECOLECCIÓN ---
        
        # Extrae SENDER (Subida) y divide por 1,000,000 para obtener Mbps
        SENDER_MBPS=$(jq -r '.end.sum_sent.bits_per_second / 1000000 | select(type=="number") // empty' "$FICHERO_TEMPORAL")
        
        # Extrae RECEIVER (Bajada) y divide por 1,000,000 para obtener Mbps
        RECEIVER_MBPS=$(jq -r '.end.sum_received.bits_per_second / 1000000 | select(type=="number") // empty' "$FICHERO_TEMPORAL")
        
        if [[ -n "$SENDER_MBPS" && -n "$RECEIVER_MBPS" ]]; then
            
            echo "  ✅ ÉXITO: ⬆️ SENDER: $SENDER_MBPS Mbps | ⬇️ RECEIVER: $RECEIVER_MBPS Mbps"
            
            # Recolectar los valores en los arrays globales
            SENDER_VALUES+=("$SENDER_MBPS")
            RECEIVER_VALUES+=("$RECEIVER_MBPS")
        else
            FALLA_MSG=$(jq -r '.error // "Falla de conexión/Iperf3 no generó JSON válido."' "$FICHERO_TEMPORAL" 2>/dev/null)
            echo "  ⚠️ FALLA EN TEST #$CONTADOR. Mensaje: $FALLA_MSG"
            NUM_FALLAS=$((NUM_FALLAS + 1))
        fi

        sleep 1 
    done
}

# --------------------------------------------------------------------
# FUNCIÓN DE ANÁLISIS Y PROMEDIO (Usa los arrays globales)
# --------------------------------------------------------------------
analizar_y_promediar() {
    echo ""
    echo "--- 📊 Iniciando Análisis y Promedio Final ---"
    
    local CORRIDAS_EXITOSAS=${#SENDER_VALUES[@]}
    local TOTAL_SENDER_FINAL=0.0
    local TOTAL_RECEIVER_FINAL=0.0

    if [ $CORRIDAS_EXITOSAS -gt 0 ]; then
        
        # Sumar todos los valores de SENDER usando bc
        for val in "${SENDER_VALUES[@]}"; do
            TOTAL_SENDER_FINAL=$(echo "scale=9; $TOTAL_SENDER_FINAL + $val" | bc)
        done

        # Sumar todos los valores de RECEIVER usando bc
        for val in "${RECEIVER_VALUES[@]}"; do
            TOTAL_RECEIVER_FINAL=$(echo "scale=9; $TOTAL_RECEIVER_FINAL + $val" | bc)
        done

        # Calcular el promedio final con bc y limitar a 2 decimales para el reporte
        PROMEDIO_SENDER=$(echo "scale=2; $TOTAL_SENDER_FINAL / $CORRIDAS_EXITOSAS" | bc)
        PROMEDIO_RECEIVER=$(echo "scale=2; $TOTAL_RECEIVER_FINAL / $CORRIDAS_EXITOSAS" | bc)

        echo "----------------------------------------------------"
        echo "Total de pruebas GENERADAS: $MAX_ITERACIONES"
        echo "Total de pruebas EXITOSAS y procesadas: $CORRIDAS_EXITOSAS"
        echo "Total de pruebas FALLIDAS/Incompletas: $NUM_FALLAS"
        echo "----------------------------------------------------"
        echo "PROMEDIO FINAL SENDER (Subida/Upload): ${PROMEDIO_SENDER} Mbps"
        echo "PROMEDIO FINAL RECEIVER (Bajada/Download): ${PROMEDIO_RECEIVER} Mbps"
    else
        echo "❌ No se encontraron datos de velocidad válidos para promediar. Revise si todas las pruebas fallaron."
    fi
    echo "----------------------------------------------------"
}

# ====================================================================
# EJECUCIÓN DEL PROGRAMA PRINCIPAL
# ====================================================================

# 1. Verificar y limpiar
install_dependencies

# 2. Ejecutar el monitoreo y generar el archivo de salida
run_iperf_monitor

# 3. Analizar y reportar (usa los datos recolectados en el paso 2)
analizar_y_promediar
