#!/bin/bash

# Add bash_libraries directory to path
__run_sh__base_path="$(dirname "$(realpath --logical "${BASH_SOURCE[0]}")")"
__run_sh__bash_libraries_relative_path="../bash_libraries"
__run_sh__bash_libraries_absolute_path=$(cd "$__run_sh__base_path" && cd "$__run_sh__bash_libraries_relative_path" && pwd)
export PATH="$__run_sh__bash_libraries_absolute_path:$PATH"

source csv_to_dat.sh || exit 1
source framework.sh || exit 1
source get_result_count.sh || exit 1
source panic.sh || exit 1
source path_join.sh || exit 1

# TODO:  Excluding gocr because of difficulty used gocr with hey
# Please keep the element ordered alphabetically!
# declare -a workloads=(ekf resize lpd gocr)
declare -a workloads=(ekf lpd resize)
declare -a multiples=(1.5 1.6 1.7 1.8 1.9 2.0)

profile() {
	local hostname="$1"
	local -r results_directory="$2"

	# ekf
	hey -disable-compression -disable-keepalive -disable-redirects -n 256 -c 1 -cpus 1 -t 0 -o csv -m GET -D "./ekf/initial_state.dat" "http://${hostname}:10000" > /dev/null

	# Resize
	hey -disable-compression -disable-keepalive -disable-redirects -n 256 -c 1 -cpus 1 -t 0 -o csv -m GET -D "./resize/shrinking_man_large.jpg" "http://${hostname}:10001" > /dev/null

	# lpd
	hey -disable-compression -disable-keepalive -disable-redirects -n 256 -c 1 -cpus 1 -t 0 -o csv -m GET -D "./lpd/Cars0.png" "http://${hostname}:10002" > /dev/null

	# gocr - Hit error. Commented out temporarily
	# hey -disable-compression -disable-keepalive -disable-redirects -n 256 -c 1 -cpus 1 -t 0 -o csv -m GET -D "./gocr/hyde.pnm" "http://${hostname}:10003" > /dev/null
}

get_baseline_execution() {
	local -r results_directory="$1"
	local -r module="$2"
	local -ir percentile="$3"

	local response_times_file="$results_directory/$module/response_times_sorted.csv"

	# Skip empty results
	local -i oks
	oks=$(wc -l < "$response_times_file")
	((oks == 0)) && return 1

	# Generate Latency Data for csv
	awk '
		BEGIN {idx = int('"$oks"' * ('"$percentile"' / 100))}
		NR==idx  {printf "%1.4f\n", $0}
	' < "$response_times_file"
}

calculate_relative_deadline() {
	local -r baseline="$1"
	local -r multiplier="$2"
	awk "BEGIN { printf \"%.0f\n\", ($baseline * $multiplier)}"
}

generate_spec() {
	local results_directory="$1"

	# Multiplier Interval and Expected Execution Percentile is currently the same for all workloads
	local -ri percentile=90
	((percentile < 50 || percentile > 99)) && panic "Percentile should be between 50 and 99 inclusive, was $percentile"

	local -A baseline_execution=()
	local -i port=10000
	local relative_deadline

	for workload in "${workloads[@]}"; do
		baseline_execution["$workload"]="$(get_baseline_execution "$results_directory" "$workload" $percentile)"
		[[ -z "${baseline_execution[$workload]}" ]] && {
			panic "Failed to get baseline execution for $workload"
			exit 1
		}

		# Generates unique module specs on different ports using the different multiples
		for multiple in "${multiples[@]}"; do
			relative_deadline=$(calculate_relative_deadline "${baseline_execution[$workload]}" "${multiple}")
			jq ". + { \
			\"admissions-percentile\": $percentile,\
			\"expected-execution-us\": ${baseline_execution[${workload}]},\
			\"name\": \"${workload}_${multiple}\",\
			\"port\": $port,\
			\"relative-deadline-us\": $relative_deadline}" \
				< "./${workload}/template.json" \
				> "./${workload}/result_${multiple}.json"
			((port++))
		done

		# Merges all of the multiple specs for a single module
		jq -s '.' ./"${workload}"/result_*.json > "./${workload}/workload_result.json"
		rm ./"${workload}"/result_*.json

	done

	# Merges all of the specs for all modules
	# Our JSON format is not spec complaint. I have to hack in a wrapping array before jq and delete it afterwards
	# expected-execution-us and admissions-percentile is only used by admissions control
	jq -s '. | flatten' ./*/workload_result.json | tail -n +2 | head -n-1 > "$results_directory/spec.json"
	rm ./*/workload_result*.json
}

# Process the experimental results and generate human-friendly results for success rate, throughput, and latency
process_results() {
	local results_directory="$1"

	for workload in "${workloads[@]}"; do
		mkdir "$results_directory/$workload"
		awk -F, '$2 == "'"$workload"'" {printf("%.0f\n", $6 / $13)}' < "$results_directory/perf.log" | sort -g > "$results_directory/$workload/response_times_sorted.csv"
	done

	generate_spec "$results_directory"

	return 0
}

experiment_server_post() {
	mv "$__run_sh__base_path/perf.log" "$RESULTS_DIRECTORY/perf.log"
	process_results "$RESULTS_DIRECTORY"
}

experiment_client() {
	local -r hostname="$1"
	local -r results_directory="$2"

	profile "$hostname" "$results_directory" || return 1
}

main "$@"
