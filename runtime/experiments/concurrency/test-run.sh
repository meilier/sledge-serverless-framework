#!/bin/bash

# This experiment is intended to document how the level of concurrent requests influence the latency, throughput, and success/failure rate

# Add bash_libraries directory to path
__run_sh__base_path="$(dirname "$(realpath --logical "${BASH_SOURCE[0]}")")"
__run_sh__bash_libraries_relative_path="../bash_libraries"
__run_sh__bash_libraries_absolute_path=$(cd "$__run_sh__base_path" && cd "$__run_sh__bash_libraries_relative_path" && pwd)
export PATH="$__run_sh__bash_libraries_absolute_path:$PATH"

source csv_to_dat.sh || exit 1
source framework.sh || exit 1
source generate_gnuplots.sh || exit 1
source get_result_count.sh || exit 1
source panic.sh || exit 1
source percentiles_table.sh || exit 1
source path_join.sh || exit 1


declare -gi iterations=10000
declare -ga concurrency=(1 20 40 60 80 100)




process_results() {
	if (($# != 1)); then
		panic "invalid number of arguments ($#, expected 1)"
		return 1
	elif ! [[ -d "$1" ]]; then
		panic "directory $1 does not exist"
		return 1
	fi

	local -r results_directory="$1"

	printf "Processing Results: "

	# Write headers to CSVs
	printf "Concurrency,Success_Rate\n" >> "$results_directory/success.csv"
	printf "Concurrency,Throughput\n" >> "$results_directory/throughput.csv"
	percentiles_table_header "$results_directory/latency.csv" "Con"

	for conn in ${concurrency[*]}; do

		if [[ ! -f "$results_directory/con$conn.csv" ]]; then
			printf "[ERR]\n"
			panic "Missing $results_directory/con$conn.csv"
			return 1
		fi

		# Calculate Success Rate for csv (percent of requests resulting in 200)
		awk -F, '
		$7 == 200 {ok++}
		END{printf "'"$conn"',%3.5f\n", (ok / '"$iterations"' * 100)}
	' < "$results_directory/con$conn.csv" >> "$results_directory/success.csv"

		# Filter on 200s, convert from s to ms, and sort
		awk -F, '$7 == 200 {print ($1 * 1000)}' < "$results_directory/con$conn.csv" \
			| sort -g > "$results_directory/con$conn-response.csv"
		
		echo "exit 0 - 666"
		exit 0

		# Get Number of 200s
		oks=$(wc -l < "$results_directory/con$conn-response.csv")
		((oks == 0)) && continue # If all errors, skip line

		# We determine duration by looking at the timestamp of the last complete request
		# TODO: Should this instead just use the client-side synthetic duration_sec value?
		duration=$(tail -n1 "$results_directory/con$conn.csv" | cut -d, -f8)

		# Throughput is calculated as the mean number of successful requests per second
		throughput=$(echo "$oks/$duration" | bc)
		printf "%d,%f\n" "$conn" "$throughput" >> "$results_directory/throughput.csv"

		# Generate Latency Data for csv
		percentiles_table_row "$results_directory/con$conn-response.csv" "$results_directory/latency.csv" "$conn"

		# Delete scratch file used for sorting/counting
		rm -rf "$results_directory/con$conn-response.csv"
	done

	# Transform csvs to dat files for gnuplot
	csv_to_dat "$results_directory/success.csv" "$results_directory/throughput.csv" "$results_directory/latency.csv"

	# Generate gnuplots
	generate_gnuplots "$results_directory" "$__run_sh__base_path" || {
		printf "[ERR]\n"
		panic "failed to generate gnuplots"
	}

	printf "[OK]\n"
	return 0
}

process_results /root/github/sledge-serverless-framework/runtime/experiments/concurrency/res/1627711982-test/edf_nopreemption