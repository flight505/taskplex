#!/usr/bin/env bash
# compare.sh — Generate head-to-head comparison report
#
# Usage: ./compare.sh <scores-dir-a> <scores-dir-b>
# Each directory should contain one JSON score file per story (from score.sh)
#
# Outputs a human-readable comparison report to stdout
# and a machine-readable summary to stdout (--json flag)
#
# Dependencies: jq, bc, bash 3.2+

set -euo pipefail

DIR_A="${1:?Usage: compare.sh <scores-dir-a> <scores-dir-b>}"
DIR_B="${2:?Usage: compare.sh <scores-dir-a> <scores-dir-b>}"
OUTPUT_JSON="${3:-}"

# ─────────────────────────────────────────────
# Collect scores from each directory
# ─────────────────────────────────────────────

collect_scores() {
  local dir="$1"
  local dimension="${2:-dq}"
  local scores=""

  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local score
    score=$(jq -r ".scores.$dimension" "$f" 2>/dev/null)
    if [ -n "$score" ] && [ "$score" != "null" ]; then
      if [ -n "$scores" ]; then
        scores="$scores $score"
      else
        scores="$score"
      fi
    fi
  done

  echo "$scores"
}

# ─────────────────────────────────────────────
# Statistical functions
# ─────────────────────────────────────────────

mean() {
  local values="$1"
  local sum="0"
  local count=0
  for v in $values; do
    sum=$(echo "scale=6; $sum + $v" | bc)
    count=$((count + 1))
  done
  if [ "$count" -gt 0 ]; then
    echo "scale=4; $sum / $count" | bc
  else
    echo "0"
  fi
}

stddev() {
  local values="$1"
  local avg
  avg=$(mean "$values")
  local sum_sq="0"
  local count=0
  for v in $values; do
    local diff
    diff=$(echo "scale=6; $v - $avg" | bc)
    sum_sq=$(echo "scale=6; $sum_sq + ($diff * $diff)" | bc)
    count=$((count + 1))
  done
  if [ "$count" -gt 1 ]; then
    echo "scale=4; sqrt($sum_sq / ($count - 1))" | bc -l
  else
    echo "0"
  fi
}

# Wilcoxon signed-rank test (simplified — reports test statistic W)
# For proper p-value, use Python scipy.stats.wilcoxon or look up W in table
wilcoxon_w() {
  local scores_a="$1"
  local scores_b="$2"

  # Convert to arrays
  local -a arr_a=($scores_a)
  local -a arr_b=($scores_b)
  local n=${#arr_a[@]}

  if [ "$n" -ne "${#arr_b[@]}" ]; then
    echo "ERROR: unequal sample sizes" >&2
    echo "0"
    return 1
  fi

  # Compute differences and absolute differences
  local -a diffs=()
  local -a abs_diffs=()
  local non_zero=0

  for ((i=0; i<n; i++)); do
    local d
    d=$(echo "scale=6; ${arr_a[$i]} - ${arr_b[$i]}" | bc)
    local abs_d
    abs_d=$(echo "scale=6; d=$d; if (d < 0) -1*d else d" | bc)
    # Skip ties (diff = 0)
    local is_zero
    is_zero=$(echo "$abs_d < 0.0001" | bc)
    if [ "$is_zero" -eq 0 ]; then
      diffs+=("$d")
      abs_diffs+=("$abs_d")
      non_zero=$((non_zero + 1))
    fi
  done

  if [ "$non_zero" -eq 0 ]; then
    echo "0"
    return 0
  fi

  # Simple rank assignment (no tie correction for simplicity)
  # Sort abs_diffs and assign ranks
  local -a sorted_indices=()
  for ((i=0; i<non_zero; i++)); do
    sorted_indices+=("$i")
  done

  # Bubble sort by abs_diff (small n, fine for 30 items)
  for ((i=0; i<non_zero-1; i++)); do
    for ((j=0; j<non_zero-i-1; j++)); do
      local cmp
      cmp=$(echo "${abs_diffs[${sorted_indices[$j]}]} > ${abs_diffs[${sorted_indices[$((j+1))]}]}" | bc)
      if [ "$cmp" -eq 1 ]; then
        local tmp="${sorted_indices[$j]}"
        sorted_indices[$j]="${sorted_indices[$((j+1))]}"
        sorted_indices[$((j+1))]="$tmp"
      fi
    done
  done

  # Compute W+ (sum of ranks for positive differences)
  local w_plus="0"
  local w_minus="0"
  for ((rank=1; rank<=non_zero; rank++)); do
    local idx="${sorted_indices[$((rank-1))]}"
    local d="${diffs[$idx]}"
    local is_positive
    is_positive=$(echo "$d > 0" | bc)
    if [ "$is_positive" -eq 1 ]; then
      w_plus=$((w_plus + rank))
    else
      w_minus=$((w_minus + rank))
    fi
  done

  # W = min(W+, W-)
  local w
  if [ "$w_plus" -lt "$w_minus" ]; then
    w="$w_plus"
  else
    w="$w_minus"
  fi

  echo "$w"
}

# Effect size: Cohen's d
cohens_d() {
  local scores_a="$1"
  local scores_b="$2"

  local mean_a mean_b sd_a sd_b
  mean_a=$(mean "$scores_a")
  mean_b=$(mean "$scores_b")
  sd_a=$(stddev "$scores_a")
  sd_b=$(stddev "$scores_b")

  # Pooled standard deviation
  local -a arr_a=($scores_a)
  local -a arr_b=($scores_b)
  local na=${#arr_a[@]}
  local nb=${#arr_b[@]}

  local pooled_sd
  pooled_sd=$(echo "scale=6; sqrt((($na - 1) * $sd_a * $sd_a + ($nb - 1) * $sd_b * $sd_b) / ($na + $nb - 2))" | bc -l)

  if [ "$(echo "$pooled_sd < 0.0001" | bc)" -eq 1 ]; then
    echo "0"
  else
    echo "scale=4; ($mean_a - $mean_b) / $pooled_sd" | bc
  fi
}

# ─────────────────────────────────────────────
# Generate report
# ─────────────────────────────────────────────

main() {
  # Get plugin names from first file in each dir
  local plugin_a plugin_b version_a version_b
  local first_a first_b
  first_a=$(ls "$DIR_A"/*.json 2>/dev/null | head -1)
  first_b=$(ls "$DIR_B"/*.json 2>/dev/null | head -1)

  if [ -z "$first_a" ] || [ -z "$first_b" ]; then
    echo "Error: no score files found in one or both directories" >&2
    exit 1
  fi

  plugin_a=$(jq -r '.plugin' "$first_a")
  plugin_b=$(jq -r '.plugin' "$first_b")
  version_a=$(jq -r '.plugin_version' "$first_a")
  version_b=$(jq -r '.plugin_version' "$first_b")

  local n_a n_b
  n_a=$(ls "$DIR_A"/*.json 2>/dev/null | wc -l | tr -d ' ')
  n_b=$(ls "$DIR_B"/*.json 2>/dev/null | wc -l | tr -d ' ')

  echo "═══════════════════════════════════════════"
  echo "  BENCHMARK RESULTS"
  echo "  $plugin_a v$version_a vs $plugin_b v$version_b"
  echo "  Date: $(date +%Y-%m-%d) | Stories: $n_a vs $n_b"
  echo "═══════════════════════════════════════════"
  echo ""

  # Overall DQ
  local dq_a dq_b
  dq_a=$(collect_scores "$DIR_A" "dq")
  dq_b=$(collect_scores "$DIR_B" "dq")

  local mean_dq_a mean_dq_b sd_dq_a sd_dq_b
  mean_dq_a=$(mean "$dq_a")
  mean_dq_b=$(mean "$dq_b")
  sd_dq_a=$(stddev "$dq_a")
  sd_dq_b=$(stddev "$dq_b")

  local delta_dq
  delta_dq=$(echo "scale=4; $mean_dq_a - $mean_dq_b" | bc)

  local d_dq
  d_dq=$(cohens_d "$dq_a" "$dq_b")

  local w_dq
  w_dq=$(wilcoxon_w "$dq_a" "$dq_b")

  echo "OVERALL DQ SCORE"
  printf "  %-15s %s ± %s\n" "$plugin_a:" "$mean_dq_a" "$sd_dq_a"
  printf "  %-15s %s ± %s\n" "$plugin_b:" "$mean_dq_b" "$sd_dq_b"
  echo "  Δ = $delta_dq (W=$w_dq, d=$d_dq)"
  echo ""

  # Per-dimension breakdown
  echo "PER-DIMENSION BREAKDOWN"
  printf "  %-15s %-10s %-10s %-8s %-6s %-8s\n" "Dimension" "$plugin_a" "$plugin_b" "Δ" "W" "d"
  printf "  %-15s %-10s %-10s %-8s %-6s %-8s\n" "─────────────" "──────────" "──────────" "────────" "──────" "────────"

  for dim in discipline correctness autonomy efficiency; do
    local scores_a scores_b m_a m_b delta w d_eff
    scores_a=$(collect_scores "$DIR_A" "$dim")
    scores_b=$(collect_scores "$DIR_B" "$dim")
    m_a=$(mean "$scores_a")
    m_b=$(mean "$scores_b")
    delta=$(echo "scale=4; $m_a - $m_b" | bc)
    w=$(wilcoxon_w "$scores_a" "$scores_b")
    d_eff=$(cohens_d "$scores_a" "$scores_b")

    local sign=""
    local is_positive
    is_positive=$(echo "$delta > 0" | bc)
    if [ "$is_positive" -eq 1 ]; then
      sign="+"
    fi

    printf "  %-15s %-10s %-10s %s%-7s %-6s %-8s\n" "$dim" "$m_a" "$m_b" "$sign" "$delta" "$w" "$d_eff"
  done

  echo ""

  # Per-tier breakdown
  echo "PER-TIER BREAKDOWN"
  for tier in T1 T2 T3 T4 T5; do
    local tier_scores_a="" tier_scores_b=""
    for f in "$DIR_A"/*.json; do
      [ -f "$f" ] || continue
      local ft
      ft=$(jq -r '.tier' "$f" 2>/dev/null)
      if [ "$ft" = "$tier" ]; then
        local s
        s=$(jq -r '.scores.dq' "$f" 2>/dev/null)
        if [ -n "$tier_scores_a" ]; then
          tier_scores_a="$tier_scores_a $s"
        else
          tier_scores_a="$s"
        fi
      fi
    done
    for f in "$DIR_B"/*.json; do
      [ -f "$f" ] || continue
      local ft
      ft=$(jq -r '.tier' "$f" 2>/dev/null)
      if [ "$ft" = "$tier" ]; then
        local s
        s=$(jq -r '.scores.dq' "$f" 2>/dev/null)
        if [ -n "$tier_scores_b" ]; then
          tier_scores_b="$tier_scores_b $s"
        else
          tier_scores_b="$s"
        fi
      fi
    done

    if [ -n "$tier_scores_a" ] && [ -n "$tier_scores_b" ]; then
      local m_a m_b delta
      m_a=$(mean "$tier_scores_a")
      m_b=$(mean "$tier_scores_b")
      delta=$(echo "scale=4; $m_a - $m_b" | bc)
      local sign=""
      if [ "$(echo "$delta > 0" | bc)" -eq 1 ]; then sign="+"; fi
      printf "  %-12s %s vs %s (%s%s)\n" "$tier:" "$m_a" "$m_b" "$sign" "$delta"
    fi
  done

  echo ""
  echo "═══════════════════════════════════════════"

  # JSON output if requested
  if [ -n "$OUTPUT_JSON" ]; then
    jq -n \
      --arg plugin_a "$plugin_a" \
      --arg plugin_b "$plugin_b" \
      --arg version_a "$version_a" \
      --arg version_b "$version_b" \
      --argjson n_a "$n_a" \
      --argjson n_b "$n_b" \
      --argjson mean_dq_a "$mean_dq_a" \
      --argjson mean_dq_b "$mean_dq_b" \
      --argjson sd_dq_a "$sd_dq_a" \
      --argjson sd_dq_b "$sd_dq_b" \
      --argjson delta_dq "$delta_dq" \
      --argjson w_dq "$w_dq" \
      --argjson d_dq "$d_dq" \
      '{
        comparison: {
          plugin_a: {name: $plugin_a, version: $version_a, stories: $n_a},
          plugin_b: {name: $plugin_b, version: $version_b, stories: $n_b}
        },
        overall: {
          mean_a: $mean_dq_a,
          mean_b: $mean_dq_b,
          sd_a: $sd_dq_a,
          sd_b: $sd_dq_b,
          delta: $delta_dq,
          wilcoxon_w: $w_dq,
          cohens_d: $d_dq
        }
      }' > "$OUTPUT_JSON"
    echo "JSON summary written to: $OUTPUT_JSON"
  fi
}

main
