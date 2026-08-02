# Paper Ablation and Baseline Results

Updated: 2026-08-01
Target URL: `https://example.org/api/v1/update.bin`

This folder contains 100 deobfuscated outputs: 20 samples for each of three PSDissect variants and two baseline tools.

## Success Criterion

A sample is counted as solved only when the complete, contiguous target URL appears in the final output. Exposing the scheme, domain, path, and file name as separate expressions is not counted as complete recovery. `SyntaxOk` only indicates that PowerShell can parse the output; it does not by itself establish successful recovery or semantic equivalence.

## Configurations

| Variant | Configuration |
| --- | --- |
| `Full` | `-RuntimeSubgraphMode Full -ExecutionStateMode Shared -PreExecutionGateMode Disabled -GlobalTimeBudgetMs 0 -DynamicTimeBudgetMs 0`; default multi-round reconstruction |
| `NoRecursiveCFG` | `-RuntimeSubgraphMode Full -DynamicDepthLimit 1 -ExecutionStateMode Shared -MaxRounds 1 -PreExecutionGateMode Disabled -GlobalTimeBudgetMs 30000 -DynamicTimeBudgetMs 5000` |
| `NoSharedRunspace` | `-RuntimeSubgraphMode Full -ExecutionStateMode Isolated -MaxRounds 1 -PreExecutionGateMode Disabled -GlobalTimeBudgetMs 30000 -DynamicTimeBudgetMs 5000` |
| `PowerPeeler` | Precomputed output supplied by the user; runtime configuration and timing metrics are unavailable. |
| `Invoke-Deobfuscation` | Precomputed output supplied by the user; runtime configuration and timing metrics are unavailable. |

## Summary

| Variant | A-STR | B-CTL | C-DYN | D-INV | Total | SyntaxOk |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Full` | 5/5 | 5/5 | 5/5 | 5/5 | 20/20 | 20/20 |
| `NoRecursiveCFG` | 5/5 | 5/5 | 0/5 | 5/5 | 15/20 | 20/20 |
| `NoSharedRunspace` | 5/5 | 0/5 | 0/5 | 0/5 | 5/20 | 20/20 |
| `PowerPeeler` | 5/5 | 5/5 | 1/5 | 0/5 | 11/20 | 20/20 |
| `Invoke-Deobfuscation` | 5/5 | 0/5 | 1/5 | 0/5 | 6/20 | 20/20 |

## Baseline Analysis

- PowerPeeler completely recovers all string-level and control-flow samples. In C-DYN, it recovers `C-iex.ps1` and `C-getnewclosure.ps1`, but does not fully materialize the URL for the dot-source, `NewScriptBlock`, or `ScriptBlock::Create` cases. It recovers none of the D-INV samples because invocation-specific values remain distributed across the shared definition or process block instead of being reconstructed as complete per-invocation results.
- Invoke-Deobfuscation completely recovers all five A-STR samples and the direct `C-iex.ps1` case. It does not fully recover B-CTL because values remain separated across functions, branches, or loops, and it does not recover the nested dynamic-code or invocation-dependent samples.
- Full PSDissect is the only configuration that recovers every class. The NoRecursiveCFG result isolates the contribution of recursive dynamic CFG expansion, while the NoSharedRunspace result isolates the contribution of preserving execution state across CFG nodes.

## Interactive Intervention Ablation

All five E-HOST samples use the same three-statement structure and produce the same CFG size and node-type sequence. The intervention point is fixed between context acquisition and payload decoding, so the measured interaction window is not affected by different intervention positions.

`State Changes` counts all runtime-state modifications applied by the analyst, including corrections or retries. `Analyst Time` measures the analyst's operation time, from the moment the context-reading node completes and the variable stack is displayed until the analyst finishes the final state change and resumes execution. The overall time result should be reported as the median and range across samples rather than as a sum.

| Sample | Required Context | Auto Recovery | Debug Recovery | State Changes | Analyst Time (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| `E-host-dependent.ps1` | Host name | Fail | success | 1 | 12.2 |
| `E-computer-name.ps1` | Computer name | Fail | success | 1 | 14.8 |
| `E-user-name.ps1` | User name | Fail | success | 2 | 10.9 |
| `E-host-user.ps1` | Host name + user name | Fail |  success| 2 | 22.7 |
| `E-domain-locale.ps1` | Domain + locale | Fail | success | 2 | 19.3 |

After measurement, the aggregate recovery improvement per state change can be reported in the accompanying text as `(Debug Solved - Auto Solved) / Total State Changes`; it does not require a separate table column.

## Layout

- `Full/`, `NoRecursiveCFG/`, `NoSharedRunspace/`, `Powerpeeler/`, and `Invoke-Deobfuscation/` each contain 20 outputs grouped by A-D class.
- `results.csv` contains 100 per-sample records. Runtime-only fields are left empty for PowerPeeler and Invoke-Deobfuscation because their execution logs were not provided.
