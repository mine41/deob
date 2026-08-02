# Ablation Mini Dataset

This mini dataset is for evaluating whether the target URL is fully exposed after deobfuscation.

Target URL:

`https://example.org/api/v1/update.bin`

Samples:

| ID | Class | File | Notes |
| --- | --- | --- | --- |
| Original | Plaintext | `original.ps1` | Baseline script with the target URL visible |
| A1 | String token | `A-string-token.ps1` | Basic string concatenation without crossing control flow |
| A2 | String token | `A-format-token.ps1` | Format-operator token assembly without crossing control flow |
| A3 | String token | `A-char-array.ps1` | Character-array string construction without crossing control flow |
| A4 | String token | `A-replace-token.ps1` | Simple token replacement without crossing control flow |
| A5 | String token | `A-join-token.ps1` | Array join token assembly without crossing control flow |
| B1 | Control flow | `B-control-flow.ps1` | Conditional + loop + function call |
| B2 | Control flow | `B-if-branch.ps1` | Branch-dependent string construction |
| B3 | Control flow | `B-for-loop.ps1` | Indexed loop over URL fragments |
| B4 | Control flow | `B-foreach-loop.ps1` | Foreach loop over URL fragments |
| B5 | Control flow | `B-switch-branch.ps1` | Switch-dependent prefix and domain selection |
| C1 | Dynamic code | `C-iex.ps1` | Two-level `Invoke-Expression` dynamic execution |
| C2 | Dynamic code | `C-scriptcreate.ps1` | Two-level `ScriptBlock::Create` with call-operator invocation |
| C3 | Dynamic code | `C-newscriptblock.ps1` | Two-level `ExecutionContext.InvokeCommand.NewScriptBlock()` execution |
| C4 | Dynamic code | `C-getnewclosure.ps1` | Two-level `ScriptBlock::Create(...).GetNewClosure()` execution |
| C5 | Dynamic code | `C-dotsource.ps1` | Two-level `ScriptBlock::Create` with dot-source invocation |
| D1 | Invocation-dependent | `D-invocation-dependent.ps1` | Same scriptblock invoked multiple times with different arguments |
| D2 | Invocation-dependent | `D-function-invocation.ps1` | Same function invoked multiple times with different arguments |
| D3 | Invocation-dependent | `D-dot-source-scriptblock.ps1` | Same scriptblock dot-sourced multiple times with different arguments |
| D4 | Invocation-dependent | `D-scriptblock-invoke-method.ps1` | Same scriptblock invoked through `.Invoke()` multiple times |
| D5 | Invocation-dependent | `D-pipeline-process-block.ps1` | Same pipeline process block executed for different input objects |
| E1 | Host-dependent | `E-host-dependent.ps1` | Decoding depends on `$Host.Name`; one intervention |
| E2 | Host-dependent | `E-computer-name.ps1` | Decoding depends on `$env:COMPUTERNAME`; one intervention |
| E3 | Host-dependent | `E-user-name.ps1` | Decoding depends on `$env:USERNAME`; one intervention |
| E4 | Host-dependent | `E-host-user.ps1` | Decoding depends on host and user names; two interventions |
| E5 | Host-dependent | `E-domain-locale.ps1` | Decoding depends on domain and locale; two interventions |

E-HOST context profiles used for the controlled intervention evaluation:

| Sample | Simulated host context |
| --- | --- |
| `E-host-dependent.ps1` | `Host.Name = ConsoleHost` |
| `E-computer-name.ps1` | `COMPUTERNAME = NODE-ALPHA` |
| `E-user-name.ps1` | `USERNAME = analyst` |
| `E-host-user.ps1` | `Host.Name = ConsoleHost`, `USERNAME = analyst` |
| `E-domain-locale.ps1` | `USERDOMAIN = LAB`, `PSCulture = en-US` |

Evaluation rule:

- A sample is counted as fully exposed only if the exact target URL appears verbatim in the recovered output.
- Partial exposure does not count.

Suggested strict ablation settings:

- Full PSDissect: `-RuntimeSubgraphMode Full -ExecutionStateMode Shared -MaxRounds 1 -PreExecutionGateMode Disabled`
- w/o recursive runtime CFG expansion: `-RuntimeSubgraphMode Full -DynamicDepthLimit 1 -ExecutionStateMode Shared -MaxRounds 1 -PreExecutionGateMode Disabled`
- w/o runtime CFG construction: `-RuntimeSubgraphMode InitialOnly -ExecutionStateMode Shared -MaxRounds 1 -PreExecutionGateMode Disabled`
- w/o shared Runspace state: `-RuntimeSubgraphMode Full -ExecutionStateMode Isolated -MaxRounds 1 -PreExecutionGateMode Disabled`

Use one round for component ablation so later reconstruction rounds do not re-parse partially exposed intermediate text and mask the removed component.
