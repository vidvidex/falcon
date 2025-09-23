import re
import sys

# Run simulation with PRINT_CYCLES to output a file that can be analyzed by this script


def parse_cycles_file(filename):
    changes = []
    pattern = r"Time (\d+): Modules running changed from (\d+) to (\d+)"

    with open(filename, "r") as f:
        for line in f:
            line = line.strip()
            match = re.match(pattern, line)
            if match:
                time = int(match.group(1))
                from_state = match.group(2)
                to_state = match.group(3)
                changes.append((time, from_state, to_state))

    return changes


def calculate_module_cycles(changes):
    # Module names corresponding to bit positions (from left to right, 0-indexed)
    module_names = [
        "COPY",
        "HASH_TO_POINT",
        "INT_TO_DOUBLE",
        "FFT_IFFT",
        "NTT_INTT",
        "COMPLEX_MUL",
        "MUL_CONST",
        "SPLIT",
        "MERGE",
        "MULT_MOD_Q",
        "CHECK_BOUND",
        "DECOMPRESS",
        "COMPRESS",
        "ADD_SUB",
        "SAMPLERZ",
    ]

    # Initialize cycle counters
    module_cycles = {module: 0 for module in module_names}

    # Track current state and when modules started running
    current_state = "000000000000000"  # Initial state (all modules off)
    module_start_times = {}  # Track when each module started running

    for time, from_state, to_state in changes:
        # First, add cycles for modules that were running until this time
        for i, bit in enumerate(current_state):
            if bit == "1" and i < len(module_names):
                module_name = module_names[i]
                if module_name in module_start_times:
                    cycles = time - module_start_times[module_name]
                    module_cycles[module_name] += cycles // 10 + 2  # +2 to account for delay in detecting modules_running change

        # Update current state
        current_state = to_state

        # Track start times for newly activated modules
        module_start_times.clear()
        for i, bit in enumerate(current_state):
            if bit == "1" and i < len(module_names):
                module_name = module_names[i]
                module_start_times[module_name] = time

    return module_cycles


def print_results(module_cycles, total_time=None):
    print("Module Cycle Analysis Results")
    print("=" * 50)
    print(f"{'Module Name':<15} {'Cycles':<12} {'Percentage':<10}")
    print("-" * 50)

    total_cycles = sum(module_cycles.values())

    for module, cycles in module_cycles.items():
        if total_time:
            percentage = (cycles / total_time) * 100 if total_time > 0 else 0
        else:
            percentage = (cycles / total_cycles) * 100 if total_cycles > 0 else 0
        print(f"{module:<15} {cycles:<12} {percentage:<7.2f}%")

    print("-" * 50)


def main():

    filename = sys.argv[1]

    changes = parse_cycles_file(filename)

    if not changes:
        print("No state changes found in the file!")
        return

    module_cycles = calculate_module_cycles(changes)

    total_time = changes[-1][0] // 10 if changes else 0

    print_results(module_cycles, total_time)


if __name__ == "__main__":
    main()
