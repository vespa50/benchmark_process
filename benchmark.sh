#!/bin/bash

# Controlla se sono stati passati programmi
if [ $# -lt 1 ]; then
    echo "Uso: $0 <programma1> [argomenti] -- <programma2> [argomenti] ..."
    exit 1
fi

# File CSV per salvare i risultati
OUTPUT_FILE="benchmark_results.csv"

# Inizializza il file CSV
echo "Programma,Tempo (ms),CPU (%),RAM Max (MB),Cache Misses,I/O Lettura (KB),I/O Scrittura (KB),GPU Utilizzo (%),Consumo Energetico (W)" > "$OUTPUT_FILE"

# Variabili per confronto finale
declare -A best_values
declare -A best_programs
categories=("Tempo (ms)" "CPU (%)" "RAM Max (MB)" "Cache Misses" "I/O Lettura (KB)" "I/O Scrittura (KB)" "GPU Utilizzo (%)" "Consumo Energetico (W)")

for category in "${categories[@]}"; do
    best_values["$category"]=99999999
    best_programs["$category"]=""
done

# Funzione per creare un grafico a barre ASCII
draw_bar() {
    local value=$1
    local max_length=20
    local num_chars=$(( (value * max_length) / 100 )) # Normalizza su 100
    local bar=""

    for ((i=0; i<num_chars; i++)); do
        bar+="█"
    done

    printf "%-20s" "$bar"
}

# Funzione per eseguire un benchmark su un programma
benchmark() {
    local program="$1"
    shift
    local args=("$@")

    echo "🛠️ Test in esecuzione: $program ${args[*]}"

    /usr/bin/time -v "${program}" "${args[@]}" > /dev/null 2> time_log.txt &  
    PID=$!
    
    wait $PID  

    TIME_MS=$(grep "Elapsed (wall clock) time" time_log.txt | awk '{print int($8 * 1000)}')
    CPU_USAGE=$(grep "Percent of CPU" time_log.txt | awk '{print $NF}')
    RAM_USAGE=$(grep "Maximum resident set size" time_log.txt | awk '{print $NF}')
    RAM_USAGE=$((RAM_USAGE / 1024))

    CACHE_MISSES=$(perf stat -e cache-misses -p $PID 2>&1 | grep "cache-misses" | awk '{print $1}')
    IO_READ=$(awk '/rchar/ {print $2}' /proc/$PID/io)
    IO_WRITE=$(awk '/wchar/ {print $2}' /proc/$PID/io)
    IO_READ_KB=$((IO_READ / 1024))
    IO_WRITE_KB=$((IO_WRITE / 1024))

    if command -v nvidia-smi &> /dev/null; then
        GPU_USAGE=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | tr -d ' ')
    else
        GPU_USAGE=0
    fi

    if command -v powerstat &> /dev/null; then
        ENERGY_USAGE=$(powerstat -d 1 1 2>/dev/null | grep "W" | awk '{print $1}')
    else
        ENERGY_USAGE=0
    fi

    echo "$program,$TIME_MS,$CPU_USAGE,$RAM_USAGE,$CACHE_MISSES,$IO_READ_KB,$IO_WRITE_KB,$GPU_USAGE,$ENERGY_USAGE" >> "$OUTPUT_FILE"

    echo -e "\n📊 Risultati per $program"
    echo "----------------------------------------"
    printf "⏱️  Tempo:       %5d ms  " "$TIME_MS"
    draw_bar $((TIME_MS / 10))
    echo ""

    printf "🖥️  CPU:         %5d %%   " "$CPU_USAGE"
    draw_bar "$CPU_USAGE"
    echo ""

    printf "💾 RAM:         %5d MB   " "$RAM_USAGE"
    draw_bar "$RAM_USAGE"
    echo ""

    printf "📀 Cache Miss:  %5d      " "$CACHE_MISSES"
    draw_bar $((CACHE_MISSES / 1000))
    echo ""

    printf "📂 I/O Lettura: %5d KB   " "$IO_READ_KB"
    draw_bar $((IO_READ_KB / 10))
    echo ""

    printf "📂 I/O Scrittura:%5d KB  " "$IO_WRITE_KB"
    draw_bar $((IO_WRITE_KB / 10))
    echo ""

    printf "🎮 GPU:         %5d %%   " "$GPU_USAGE"
    draw_bar "$GPU_USAGE"
    echo ""

    printf "🔋 Energia:     %5d W    " "$ENERGY_USAGE"
    draw_bar $((ENERGY_USAGE * 2))
    echo ""

    echo "✅ Benchmark completato per $program"
    echo "----------------------------------------"

    # Confronto per trovare il migliore per ogni categoria
    values=("$TIME_MS" "$CPU_USAGE" "$RAM_USAGE" "$CACHE_MISSES" "$IO_READ_KB" "$IO_WRITE_KB" "$GPU_USAGE" "$ENERGY_USAGE")
    index=0

    for category in "${categories[@]}"; do
        if [[ ${values[$index]} -lt ${best_values["$category"]} ]]; then
            best_values["$category"]=${values[$index]}
            best_programs["$category"]="$program"
        fi
        ((index++))
    done
}

# Analizza i programmi separati da "--"
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
        shift
    else
        program="$1"
        shift
        args=()
        
        while [[ $# -gt 0 && "$1" != "--" ]]; do
            args+=("$1")
            shift
        done

        benchmark "$program" "${args[@]}"
    fi
done

echo -e "\n📊📊📊 CONFRONTO FINALE 📊📊📊"
echo "----------------------------------------"
for category in "${categories[@]}"; do
    printf "%-20s: %-15s (%d)\n" "$category" "${best_programs[$category]}" "${best_values[$category]}"
done
echo "📊 Benchmark completato! Risultati salvati in $OUTPUT_FILE"
